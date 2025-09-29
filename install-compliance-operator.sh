#!/bin/bash
set -euo pipefail

NAMESPACE="openshift-compliance"
OPERATOR_NAME="compliance-operator"
SUBSCRIPTION_NAME="compliance-operator-sub"

# Optional: choose storage bootstrap provider when no default SC exists: lvms|local-path|none
STORAGE_PROVIDER="lvms"
FORCE_STORAGE_BOOTSTRAP=false
SKIP_STORAGE_BOOTSTRAP=false

usage() {
cat <<USAGE
Usage: $(basename "$0") [options]

Install the Compliance Operator into namespace '${NAMESPACE}' and ensure a usable default StorageClass.

Options:
  --storage <provider>          Storage bootstrap provider when no default SC exists (default: lvms)
                                Accepted: lvms | local-path | none
  --force-storage-bootstrap     Force storage bootstrap even if a default StorageClass already exists
  --skip-storage-bootstrap      Skip storage bootstrap even if no default StorageClass check passes
  --co-ref <ref>                Git ref or release tag for Compliance Operator (default: latest release)
  -h, --help                    Show this help and exit

Notes:
  - If the cluster already has a default StorageClass backed by HostPath/CRC, storage bootstrap is skipped.
  - Storage bootstrap is delegated to ./bootstrap-storage.sh with the selected provider.
  - Set KUBECONFIG to choose a specific cluster context, e.g.:
      KUBECONFIG=/path/to/kubeconfig $(basename "$0") --storage lvms
USAGE
}
while [[ $# -gt 0 ]]; do
	case "$1" in
		--storage)
			STORAGE_PROVIDER="$2"; shift 2;;
		--force-storage-bootstrap)
			FORCE_STORAGE_BOOTSTRAP=true; shift;;
		--skip-storage-bootstrap)
			SKIP_STORAGE_BOOTSTRAP=true; shift;;
		--co-ref)
			CO_REF="$2"; shift 2;;
		-h|--help)
			usage; exit 0;;
		*)
			shift;;
	esac
done

echo "[PRECHECK] Ensuring 'openshift-marketplace' is healthy before proceeding..."
if ! oc get ns openshift-marketplace &>/dev/null; then
	echo "[ERROR] Namespace 'openshift-marketplace' not found. Ensure you're connected to an OpenShift cluster."
	exit 1
fi

echo "[PRECHECK] Waiting up to 5m for non-completed pods in 'openshift-marketplace' to be Ready..."
# Gather only pods that are not in Succeeded (Completed) phase (compatible with older bash)
MKTPODS=$(oc -n openshift-marketplace get pods -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | tr '\n' ' ' | xargs || true)
if [[ -n "$MKTPODS" ]]; then
	if ! oc -n openshift-marketplace wait --for=condition=Ready pod $MKTPODS --timeout=300s; then
		echo "[ERROR] Not all non-completed pods in 'openshift-marketplace' became Ready within the timeout. Current pod statuses:"
		oc -n openshift-marketplace get pods -o wide || true
		exit 1
	fi
else
	echo "[PRECHECK] No non-completed pods found in 'openshift-marketplace'; continuing."
fi

# Detect CRC and decide whether to skip storage bootstrap
SERVER=$(oc whoami --show-server 2>/dev/null || true)
IS_CRC=false
if [[ "$SERVER" =~ crc\.testing ]]; then
	IS_CRC=true
fi

SKIP_BOOTSTRAP=false
if [[ "$IS_CRC" == true ]]; then
	SKIP_BOOTSTRAP=true
fi

# Determine default SC; if one exists, prefer to skip unless forced
DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
if [[ -z "$DEFAULT_SC" ]]; then
	DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
fi

if [[ -n "$DEFAULT_SC" ]]; then
	SKIP_BOOTSTRAP=true
fi

# Honor explicit flags
if [[ "$FORCE_STORAGE_BOOTSTRAP" == true ]]; then
	SKIP_BOOTSTRAP=false
fi
if [[ "$SKIP_STORAGE_BOOTSTRAP" == true ]]; then
	SKIP_BOOTSTRAP=true
fi

if [[ "$SKIP_BOOTSTRAP" == true ]]; then
	echo "[INFO] Skipping storage bootstrap. Server='$SERVER' SC='$DEFAULT_SC'"
else
	SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
	BOOTSTRAP_ARGS=(--storage "$STORAGE_PROVIDER" --namespace "$NAMESPACE")
	if [[ "$FORCE_STORAGE_BOOTSTRAP" == true ]]; then BOOTSTRAP_ARGS+=(--force-storage-bootstrap); fi
	DEFAULT_SC=$("$SCRIPT_DIR/bootstrap-storage.sh" "${BOOTSTRAP_ARGS[@]}")
	if [[ -z "$DEFAULT_SC" ]]; then
		echo "[ERROR] Failed to detect default StorageClass after bootstrap." >&2
		exit 1
	fi
fi
echo "[INFO] Default StorageClass detected: $DEFAULT_SC"



CO_REPO_OWNER="ComplianceAsCode"
CO_REPO_NAME="compliance-operator"
# Allow environment override via COMPLIANCE_OPERATOR_REF
CO_REF="${CO_REF:-${COMPLIANCE_OPERATOR_REF:-}}"

get_latest_release_tag() {
    curl -fsSL "https://api.github.com/repos/$CO_REPO_OWNER/$CO_REPO_NAME/releases/latest" 2>/dev/null \
    | grep -m1 '"tag_name"' \
    | sed -E 's/.*"tag_name"\s*:\s*"([^"]+)".*/\1/'
}

if [[ -z "$CO_REF" ]]; then
    echo "[INFO] Resolving latest $CO_REPO_OWNER/$CO_REPO_NAME release tag from GitHub..."
    CO_REF=$(get_latest_release_tag || true)
fi

if [[ -z "$CO_REF" ]]; then
    echo "[WARN] Could not determine latest release (rate limit or network issue). Falling back to 'master'."
    CO_REF="master"
else
    echo "[INFO] Using Compliance Operator ref: $CO_REF"
fi

BASE_RAW="https://raw.githubusercontent.com/$CO_REPO_OWNER/$CO_REPO_NAME/$CO_REF"

echo "[INFO] Creating namespace: $NAMESPACE"
oc apply -f "$BASE_RAW/config/ns/ns.yaml"

echo "[INFO] Creating OperatorGroup"
oc apply -f "$BASE_RAW/config/catalog/catalog-source.yaml"

echo "[INFO] Subscribing to Compliance Operator from Red Hat"
oc apply -f "$BASE_RAW/config/catalog/operator-group.yaml"

echo "[INFO] Creating Subscription for Compliance Operator"
oc apply -f "$BASE_RAW/config/catalog/subscription.yaml"

echo "[INFO] Waiting for Subscription to populate installedCSV..."
for i in {1..30}; do
	echo "Attempt number $i"
	CSV=$(oc get subscription $SUBSCRIPTION_NAME -n $NAMESPACE -o jsonpath='{.status.installedCSV}' || true)
	if [[ -n "$CSV" ]]; then
		echo "[INFO] Found installedCSV: $CSV"
		break
	fi
	echo "[WAIT] installedCSV not found yet, retrying... ($i/30)"
	sleep 10
done

if [[ -z "$CSV" ]]; then
	echo "[ERROR] installedCSV was not populated. Exiting."
	exit 1
fi

echo "[INFO] Waiting for ClusterServiceVersion ($CSV) to be succeeded..."
for i in {1..30}; do
	PHASE=$(oc get clusterserviceversion "$CSV" -n "$NAMESPACE" -o jsonpath='{.status.phase}' || true)
	echo "[WAIT] ClusterServiceVersion phase: $PHASE ($i/30)"
	if [[ "$PHASE" == "Succeeded" ]]; then
		echo "[INFO] ClusterServiceVersion $CSV is Succeeded."
		break
	fi
	sleep 10
done

if [[ "$PHASE" != "Succeeded" ]]; then
	echo "[ERROR] ClusterServiceVersion $CSV did not reach Succeeded phase. Exiting."
	exit 1
fi

echo "[SUCCESS] Compliance Operator installed successfully."
oc get pods -n $NAMESPACE

echo "[INFO] Waiting up to 5m for non-completed pods in '$NAMESPACE' to be Ready..."
NSPODS=$(oc -n "$NAMESPACE" get pods -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | tr '\n' ' ' | xargs || true)
if [[ -n "$NSPODS" ]]; then
    if ! oc -n "$NAMESPACE" wait --for=condition=Ready pod $NSPODS --timeout=300s; then
        echo "[WARN] Not all non-completed pods in '$NAMESPACE' became Ready within the timeout. Current pod statuses:"
        oc -n "$NAMESPACE" get pods -o wide || true
    fi
else
    echo "[INFO] No non-completed pods found in '$NAMESPACE'; continuing."
fi

echo "[NEXT STEP] To schedule a periodic compliance scan, run:"
echo "  ./apply-periodic-scan.sh"
