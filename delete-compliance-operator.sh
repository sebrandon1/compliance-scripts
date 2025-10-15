#!/bin/bash
set -euo pipefail

NAMESPACE="openshift-compliance"
OPERATOR_NAME="compliance-operator"

# Flags
PURGE_CRDS=false
USE_MAKE_TEAR_DOWN=false
REPO_PATH="${COMPLIANCE_OPERATOR_REPO:-}"

# Parse args
while [[ $# -gt 0 ]]; do
	case "$1" in
	--purge-crds)
		PURGE_CRDS=true
		shift
		;;
	--use-make-tear-down)
		USE_MAKE_TEAR_DOWN=true
		shift
		;;
	--repo-path)
		REPO_PATH="$2"
		shift 2
		;;
	--repo-path=*)
		REPO_PATH="${1#*=}"
		shift
		;;
	*)
		# ignore unknown flags for forward compatibility
		shift
		;;
	esac
done

FORCE_DELETE_NS_SCRIPT="$(dirname "$0")/force-delete-namespace.sh"
NAMESPACE_DELETE_TIMEOUT_SECONDS=60

echo "[INFO] Beginning uninstall of $OPERATOR_NAME from namespace '$NAMESPACE'"

# If requested, try to use upstream make target first
if [[ "$USE_MAKE_TEAR_DOWN" == true ]]; then
	if [[ -z "$REPO_PATH" ]]; then
		echo "[WARN] --use-make-tear-down specified but no repo path provided. Set COMPLIANCE_OPERATOR_REPO or pass --repo-path. Falling back to scripted removal."
	else
		if [[ -f "$REPO_PATH/Makefile" ]]; then
			echo "[INFO] Running 'make tear-down' in $REPO_PATH"
			if make -C "$REPO_PATH" tear-down; then
				# Verify namespace deletion; if gone, we are done
				if ! oc get ns "$NAMESPACE" &>/dev/null; then
					echo "[SUCCESS] 'make tear-down' completed and namespace is removed."
					exit 0
				else
					echo "[WARN] Namespace '$NAMESPACE' still present after 'make tear-down'. Continuing with scripted cleanup..."
				fi
			else
				echo "[WARN] 'make tear-down' failed. Continuing with scripted cleanup..."
			fi
		else
			echo "[WARN] Makefile not found at $REPO_PATH. Falling back to scripted removal."
		fi
	fi
fi

# Per Compliance Operator docs (Namespace removal), proactively strip finalizers from
# namespaced Compliance CRs to prevent the namespace from hanging in Terminating.
remove_finalizers_from_crs() {
	local kinds=(
		"compliancesuites.compliance.openshift.io"
		"compliancescans.compliance.openshift.io"
		"compliancecheckresults.compliance.openshift.io"
		"complianceremediations.compliance.openshift.io"
		"scansettings.compliance.openshift.io"
		"scansettingbindings.compliance.openshift.io"
		"profilebundles.compliance.openshift.io"
		"profiles.compliance.openshift.io"
		"tailoredprofiles.compliance.openshift.io"
		"rules.compliance.openshift.io"
		"variables.compliance.openshift.io"
	)

	for kind in "${kinds[@]}"; do
		NAMES=$(oc get "$kind" -n "$NAMESPACE" -o name 2>/dev/null || true)
		if [[ -n "$NAMES" ]]; then
			echo "[INFO] Removing finalizers from $kind objects (if present)"
			for res in $NAMES; do
				# Best-effort: remove any finalizers to avoid deletion hangs
				oc patch "$res" -n "$NAMESPACE" --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
			done
		fi
	done
}

remove_finalizers_from_crs

# Proactively delete namespaced Compliance custom resources to avoid finalizers blocking namespace deletion
echo "[INFO] Deleting Compliance custom resources in namespace '$NAMESPACE'"
RESOURCES_TO_DELETE=(
	"compliancesuites.compliance.openshift.io"
	"compliancescans.compliance.openshift.io"
	"compliancecheckresults.compliance.openshift.io"
	"complianceremediations.compliance.openshift.io"
	"scansettings.compliance.openshift.io"
	"scansettingbindings.compliance.openshift.io"
	"profilebundles.compliance.openshift.io"
	"profiles.compliance.openshift.io"
	"tailoredprofiles.compliance.openshift.io"
	"rules.compliance.openshift.io"
	"variables.compliance.openshift.io"
	"installplan"
)
for kind in "${RESOURCES_TO_DELETE[@]}"; do
	NAMES=$(oc get "$kind" -n "$NAMESPACE" -o name 2>/dev/null || true)
	if [[ -n "$NAMES" ]]; then
		echo "[INFO] Deleting $kind objects:"
		echo "$NAMES" | sed 's/^/\t- /'
		oc delete $NAMES -n "$NAMESPACE" --ignore-not-found=true || true
	else
		echo "[INFO] No $kind objects found in $NAMESPACE."
	fi
done

# Delete Subscriptions whose spec.name matches the operator package (handles nonstandard Subscription names)
SUBSCRIPTIONS=$(oc get subscription -n "$NAMESPACE" --no-headers -o custom-columns=NAME:.metadata.name,PKG:.spec.name 2>/dev/null | awk -v pkg="$OPERATOR_NAME" '$2==pkg {print $1}')
if [[ -n "$SUBSCRIPTIONS" ]]; then
	echo "[INFO] Deleting Subscriptions referencing package '$OPERATOR_NAME' in $NAMESPACE"
	for sub in $SUBSCRIPTIONS; do
		echo "[INFO] Deleting Subscription: $sub"
		oc delete subscription "$sub" -n "$NAMESPACE" --ignore-not-found=true
	done
else
	echo "[INFO] No Subscriptions referencing '$OPERATOR_NAME' found in $NAMESPACE. Skipping."
fi

# Delete all CSVs for the operator in the namespace (there can be multiple)
CSV_NAMES=$(oc get csv -n "$NAMESPACE" -o name 2>/dev/null | grep "$OPERATOR_NAME" || true)
if [[ -n "$CSV_NAMES" ]]; then
	echo "[INFO] Deleting ClusterServiceVersions:"
	echo "$CSV_NAMES" | sed 's/^/\t- /'
	oc delete $CSV_NAMES -n "$NAMESPACE" --ignore-not-found=true
else
	echo "[INFO] No ClusterServiceVersions found for '$OPERATOR_NAME' in $NAMESPACE. Skipping."
fi

# Delete OperatorGroup(s) in the namespace
echo "[INFO] Deleting OperatorGroup(s) in $NAMESPACE (if any)"
oc delete operatorgroup --all -n "$NAMESPACE" --ignore-not-found=true

# Delete CatalogSource(s) scoped to the namespace (does not touch global sources)
echo "[INFO] Deleting CatalogSource(s) in $NAMESPACE (if any)"
oc delete catalogsource --all -n "$NAMESPACE" --ignore-not-found=true

# Optionally purge Compliance CRDs (cluster-scoped) after uninstall
if [[ "$PURGE_CRDS" == true ]]; then
	echo "[WARN] Purging Compliance CRDs (cluster-scoped). This removes all Compliance API types."
	CRDS=$(oc get crd -o name 2>/dev/null | grep -E "\\.compliance\\.openshift\\.io$" || true)
	if [[ -n "$CRDS" ]]; then
		echo "$CRDS" | sed 's/^/\t- /'
		oc delete $CRDS || true
	else
		echo "[INFO] No Compliance CRDs found to purge."
	fi
fi

# Delete the Namespace and wait briefly, then force-delete if stuck
if oc get namespace "$NAMESPACE" &>/dev/null; then
	echo "[INFO] Deleting Namespace: $NAMESPACE"
	oc delete namespace "$NAMESPACE" --ignore-not-found=true

	echo "[INFO] Waiting up to ${NAMESPACE_DELETE_TIMEOUT_SECONDS}s for namespace to be removed..."
	for i in $(seq 1 $((NAMESPACE_DELETE_TIMEOUT_SECONDS / 5))); do
		if ! oc get ns "$NAMESPACE" &>/dev/null; then
			echo "[SUCCESS] Namespace '$NAMESPACE' has been deleted."
			break
		fi
		sleep 5
		if [[ $i -eq $((NAMESPACE_DELETE_TIMEOUT_SECONDS / 5)) ]]; then
			STATUS=$(oc get ns "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
			if [[ "$STATUS" == "Terminating" ]]; then
				echo "[WARN] Namespace '$NAMESPACE' is stuck terminating. Attempting force deletion..."
				if [[ -x "$FORCE_DELETE_NS_SCRIPT" ]]; then
					"$FORCE_DELETE_NS_SCRIPT" "$NAMESPACE"
				else
					echo "[ERROR] Force delete script not found or not executable: $FORCE_DELETE_NS_SCRIPT"
					echo "[HINT] Run: ./force-delete-namespace.sh $NAMESPACE"
				fi
			else
				echo "[INFO] Namespace status: $STATUS"
			fi
		fi
	done
else
	echo "[INFO] Namespace $NAMESPACE not found. Skipping."
fi

echo "[SUCCESS] Compliance Operator and related resources have been removed."
