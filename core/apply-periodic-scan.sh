#!/bin/bash
# apply-periodic-scan.sh - Apply periodic compliance scan configuration
#
# Usage: ./core/apply-periodic-scan.sh [OPTIONS]
#
# Options:
#   -n, --namespace    Namespace for the scan (default: openshift-compliance)
#   --no-pvc           Skip PVC configuration
#   --dry-run          Preview changes without applying
#   -h, --help         Show this help message

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
	# shellcheck source=../lib/common.sh
	source "$SCRIPT_DIR/lib/common.sh"
	load_env
else
	# Fallback if common.sh doesn't exist
	log_info() { echo "[INFO] $*"; }
	log_error() { echo "[ERROR] $*" >&2; }
	log_success() { echo "[SUCCESS] $*"; }
	DRY_RUN=false
fi

# Defaults (can be overridden by .env or CLI flags)
NAMESPACE="${COMPLIANCE_NAMESPACE:-openshift-compliance}"
NO_PVC="${NO_PVC:-false}"
DRY_RUN="${DRY_RUN:-false}"

usage() {
	echo "Usage: $0 [OPTIONS]"
	echo ""
	echo "Apply periodic compliance scan configuration (E8 + CIS profiles)."
	echo ""
	echo "Options:"
	echo "  -n, --namespace    Namespace for the scan (default: $NAMESPACE)"
	echo "  --no-pvc           Skip PVC configuration for rawResultStorage"
	echo "  --dry-run          Preview changes without applying"
	echo "  -h, --help         Show this help message"
	echo ""
	echo "Environment variables: COMPLIANCE_NAMESPACE, NO_PVC, SC_NAME, RAW_SIZE, ROTATION"
	exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	-n | --namespace)
		NAMESPACE="$2"
		shift 2
		;;
	--no-pvc)
		NO_PVC=true
		shift
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	-h | --help)
		usage
		;;
	*)
		log_error "Unknown option: $1"
		usage
		;;
	esac
done

# ============================================================================
# STORAGE CLASS DETECTION
# ============================================================================

if [[ "${NO_PVC}" != "true" ]]; then
	if [[ -z "${SC_NAME:-}" ]]; then
		# First, try to get the default StorageClass
		SC_NAME=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || true)

		# If no default, prefer crc-csi-hostpath-provisioner (recommended for CRC)
		if [[ -z "${SC_NAME:-}" ]] && oc get sc crc-csi-hostpath-provisioner &>/dev/null; then
			SC_NAME=crc-csi-hostpath-provisioner
		fi

		# Fall back to any available StorageClass
		if [[ -z "${SC_NAME:-}" ]]; then
			SC_NAME=$(oc get sc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
		fi
	fi
	# Storage defaults aligned with CRD defaults
	RAW_SIZE="${RAW_SIZE:-1Gi}"
	ROTATION="${ROTATION:-3}"
fi

# ============================================================================
# MAIN
# ============================================================================

log_info "Applying periodic scan configuration..."
log_info "  Namespace: $NAMESPACE"
log_info "  PVC Storage: $([ "$NO_PVC" == "true" ] && echo "disabled" || echo "enabled (${SC_NAME:-auto})")"

if [[ "$DRY_RUN" == "true" ]]; then
	log_info "[DRY-RUN] Validating resources without applying..."
fi

# Build the ScanSetting YAML
SCANSETTING_YAML=$(
	cat <<EOF
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSetting
metadata:
  name: periodic-setting
  namespace: $NAMESPACE
schedule: "0 1 * * *"
$(
		if [[ "${NO_PVC}" != "true" ]]; then
			cat <<YML
rawResultStorage:
    storageClassName: ${SC_NAME}
    size: "${RAW_SIZE}"
    rotation: ${ROTATION}
    tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
    - key: node.kubernetes.io/not-ready
      operator: Exists
      effect: NoExecute
      tolerationSeconds: 300
    - key: node.kubernetes.io/unreachable
      operator: Exists
      effect: NoExecute
      tolerationSeconds: 300
    - key: node.kubernetes.io/memory-pressure
      operator: Exists
      effect: NoSchedule
YML
		fi
	)
roles:
  - worker
  - master
EOF
)

# ScanSettingBinding for E8 profiles
E8_BINDING_YAML=$(
	cat <<EOF
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: periodic-e8
  namespace: $NAMESPACE
profiles:
  - name: rhcos4-e8
    kind: Profile
    apiGroup: compliance.openshift.io/v1alpha1
  - name: ocp4-e8
    kind: Profile
    apiGroup: compliance.openshift.io/v1alpha1
settingsRef:
  name: periodic-setting
  kind: ScanSetting
  apiGroup: compliance.openshift.io/v1alpha1
EOF
)

# ScanSettingBinding for CIS profile
CIS_BINDING_YAML=$(
	cat <<EOF
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: cis-scan
  namespace: $NAMESPACE
profiles:
  - name: ocp4-cis
    kind: Profile
    apiGroup: compliance.openshift.io/v1alpha1
settingsRef:
  name: periodic-setting
  kind: ScanSetting
  apiGroup: compliance.openshift.io/v1alpha1
EOF
)

# Apply or dry-run resources
if [[ "$DRY_RUN" == "true" ]]; then
	echo "---"
	echo "$SCANSETTING_YAML"
	echo "---"
	echo "$E8_BINDING_YAML"
	echo "---"
	echo "$CIS_BINDING_YAML"
	echo "---"

	log_info "[DRY-RUN] Validating ScanSetting..."
	echo "$SCANSETTING_YAML" | oc apply --dry-run=server -f -

	log_info "[DRY-RUN] Validating E8 ScanSettingBinding..."
	echo "$E8_BINDING_YAML" | oc apply --dry-run=server -f -

	log_info "[DRY-RUN] Validating CIS ScanSettingBinding..."
	echo "$CIS_BINDING_YAML" | oc apply --dry-run=server -f -

	log_info "[DRY-RUN] Validation passed. Run without --dry-run to apply."
else
	echo "$SCANSETTING_YAML" | oc apply -f -
	echo "$E8_BINDING_YAML" | oc apply -f -
	echo "$CIS_BINDING_YAML" | oc apply -f -

	log_success "ScanSetting 'periodic-setting' applied in namespace '$NAMESPACE'."
	log_info "ScanSettingBindings created:"
	echo "       - periodic-e8 (rhcos4-e8-master, rhcos4-e8-worker, ocp4-e8)"
	echo "       - cis-scan (ocp4-cis)"
	echo ""
	log_info "To create an on-demand scan, run: ./core/create-scan.sh"
fi
