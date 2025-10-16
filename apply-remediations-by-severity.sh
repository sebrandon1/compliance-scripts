#!/bin/bash
set -euo pipefail

usage() {
	echo "Usage: $0 <severity>"
	echo "  <severity>: high | medium | low"
	exit 1
}

if [[ $# -lt 1 ]]; then
	usage
fi

SEVERITY="$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')"
case "$SEVERITY" in
high | medium | low) ;;
*)
	echo "[ERROR] Invalid severity: $SEVERITY"
	usage
	;;
	# no default
esac

if ! command -v oc >/dev/null 2>&1; then
	echo "[ERROR] 'oc' CLI is required. Please install and login to your cluster."
	exit 1
fi

# Require yq for metadata injection when applying raw YAMLs
if ! command -v yq >/dev/null 2>&1; then
	echo "[ERROR] 'yq' is required. Please install it (e.g., brew install yq)."
	exit 1
fi

# Verify we are logged into a cluster
if ! oc whoami >/dev/null 2>&1; then
	echo "[ERROR] Unable to connect to the cluster. Please run 'oc login' and retry."
	exit 1
fi

NAMESPACE="openshift-compliance"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$REPO_DIR/complianceremediations"

# Precompute severity-matched combined YAMLs for visibility (exclude complianceremediations/combo)
MATCHED_FILES=$(
	(
		# Root-level combined files matching *-<severity>-combo.yaml
		find "$SRC_DIR" -maxdepth 1 -type f -name "*-$SEVERITY-combo.yaml" 2>/dev/null || true
		# Per-severity subdirectory combined files only: complianceremediations/<severity>/*-combo.yaml
		find "$SRC_DIR/$SEVERITY" -type f -name "*-combo.yaml" 2>/dev/null || true
	) | sort -u
)

echo "[INFO] Applying combined remediation YAMLs (no ComplianceRemediation patching)."

if [[ ! -d "$SRC_DIR" ]]; then
	echo "[WARN] Source directory not found: $SRC_DIR"
	exit 0
fi

# Collect YAML files by severity from allowed locations/patterns
FILES_TO_APPLY=$(
	(
		# Root-level combined files matching *-<severity>-combo.yaml
		find "$SRC_DIR" -maxdepth 1 -type f -name "*-$SEVERITY-combo.yaml" 2>/dev/null || true
		# Per-severity subdirectory combined files only: complianceremediations/<severity>/*-combo.yaml
		find "$SRC_DIR/$SEVERITY" -type f -name "*-combo.yaml" 2>/dev/null || true
	) | sort -u
)

if [[ -z "$FILES_TO_APPLY" ]]; then
	echo "[WARN] No remediation YAMLs found for severity '$SEVERITY' under $SRC_DIR."
	exit 0
fi

COUNT=$(printf "%s\n" "$FILES_TO_APPLY" | grep -c ".")
echo "[INFO] Applying $COUNT remediation YAML(s) for severity '$SEVERITY'..."

report_path="$REPO_DIR/applied-yamls-$SEVERITY-$(date -u +%Y%m%dT%H%M%SZ).txt"
echo "# YAML apply report ($SEVERITY) - $(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$report_path"
echo "file,reboot_hint,result" >>"$report_path"

# Use a temp workspace for metadata-injected files
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
while IFS= read -r file; do
	[[ -z "$file" ]] && continue
	# Prepare metadata-injected temp file mirroring organize-machine-configs.sh behavior
	base_name=$(basename "$file")
	base_name_no_prefix=${base_name#75-}
	new_name="75-${base_name_no_prefix}"
	metadata_name="75-${base_name_no_prefix%.yaml}"
	kind=$(yq e '.kind' "$file" 2>/dev/null || echo "")
	modified_file="$TMP_DIR/$new_name"

	# Determine reboot hint (best-effort): MachineConfig changes typically roll MCPs and reboot nodes
	reboot_hint="No"
	if [[ "$kind" == "MachineConfig" ]]; then
		reboot_hint="Yes"
		# Derive role: prefer existing label, then filename hints, then content hints, default worker
		role=$(yq e '.metadata.labels["machineconfiguration.openshift.io/role"]' "$file" 2>/dev/null || echo "")
		if [[ -z "$role" || "$role" == "null" ]]; then
			if [[ "$base_name" == *"master"* ]]; then
				role="master"
			elif [[ "$base_name" == *"worker"* ]]; then
				role="worker"
			else
				first_lines=$(head -n 3 "$file" 2>/dev/null || true)
				has_master=$(echo "$first_lines" | grep -c "master" || true)
				has_worker=$(echo "$first_lines" | grep -c "worker" || true)
				if [[ $has_master -gt 0 && $has_worker -gt 0 ]]; then
					role="worker"
				elif [[ $has_master -gt 0 ]]; then
					role="master"
				elif [[ $has_worker -gt 0 ]]; then
					role="worker"
				else
					if grep -q "master" "$file" 2>/dev/null; then
						role="master"
					elif grep -q "worker" "$file" 2>/dev/null; then
						role="worker"
					else
						role="worker"
					fi
				fi
			fi
		fi
		# Inject metadata.name and role label
		yq ".metadata.name = \"$metadata_name\" | .metadata.labels.[\"machineconfiguration.openshift.io/role\"] = \"$role\"" "$file" >"$modified_file"
	elif [[ "$kind" == "APIServer" ]]; then
		# APIServer resources should always have metadata.name=cluster
		yq ".metadata.name = \"cluster\"" "$file" >"$modified_file"
	else
		# Generic case: ensure a stable metadata.name is set
		yq ".metadata.name = \"$metadata_name\"" "$file" >"$modified_file"
	fi

	# Validate the transformed YAML
	if ! yq e '.' "$modified_file" >/dev/null 2>&1; then
		echo "[WARN] Transformed YAML is invalid for $file. Skipping."
		echo "$file,invalid-transformed-yaml" >>"$report_path"
		continue
	fi

	# Server-side dry-run first
	echo "[DRY-RUN] oc apply --dry-run=server -f $modified_file"
	oc apply --dry-run=server -f "$modified_file"

	echo "[APPLY] oc apply -f $modified_file (from $file) | reboot_hint=$reboot_hint"
	result=$(oc apply -f "$modified_file" 2>&1 || true)
	echo "$result"
	echo "$file,$reboot_hint,${result//,/;}" >>"$report_path"

	# Wait for reconciliation where appropriate
	if [[ "$kind" == "MachineConfig" ]]; then
		echo "[WAIT] Waiting for MCP/$role to become Updated=True"
		oc wait mcp/"$role" --for=condition=Updated=True --timeout=45m
		oc get mcp "$role" -o wide || true
	elif [[ "$kind" == "APIServer" ]]; then
		echo "[WAIT] Waiting for kube-apiserver operator Available=True"
		oc wait co/kube-apiserver --for=condition=Available=True --timeout=10m || true
	else
		# Basic existence check for other resource kinds
		oc get -f "$modified_file" >/dev/null 2>&1 || true
	fi
done <<<"$FILES_TO_APPLY"

echo "[SUCCESS] Completed applying remediations for severity '$SEVERITY'."
echo "[INFO] Wrote YAML apply report to $report_path"
