#!/bin/bash
# create-scan.sh - Create a compliance scan using ScanSettingBinding
#
# Usage: ./core/create-scan.sh [OPTIONS]
#
# Options:
#   -n, --namespace    Namespace for the scan (default: openshift-compliance)
#   -p, --profile      Profile to scan against (default: ocp4-cis)
#   -s, --scan-name    Name of the scan (default: cis-scan)
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
fi

# Defaults (can be overridden by .env or CLI flags)
NAMESPACE="${COMPLIANCE_NAMESPACE:-openshift-compliance}"
PROFILE="${SCAN_PROFILE:-ocp4-cis}"
SCAN_NAME="cis-scan"
DRY_RUN=false

usage() {
	echo "Usage: $0 [OPTIONS]"
	echo ""
	echo "Create a compliance scan using ScanSettingBinding."
	echo ""
	echo "Options:"
	echo "  -n, --namespace    Namespace for the scan (default: $NAMESPACE)"
	echo "  -p, --profile      Profile to scan against (default: $PROFILE)"
	echo "  -s, --scan-name    Name of the scan (default: $SCAN_NAME)"
	echo "  --dry-run          Preview changes without applying"
	echo "  -h, --help         Show this help message"
	echo ""
	echo "Available profiles:"
	echo "  CIS:      ocp4-cis, ocp4-cis-1-7, ocp4-cis-node, ocp4-cis-node-1-7"
	echo "  NIST:     ocp4-moderate, ocp4-moderate-rev-4, ocp4-moderate-node, ocp4-moderate-node-rev-4"
	echo "            rhcos4-moderate, rhcos4-moderate-rev-4"
	echo "  PCI-DSS:  ocp4-pci-dss, ocp4-pci-dss-3-2, ocp4-pci-dss-4-0"
	echo "            ocp4-pci-dss-node, ocp4-pci-dss-node-3-2, ocp4-pci-dss-node-4-0"
	echo ""
	echo "Environment variables: COMPLIANCE_NAMESPACE, SCAN_PROFILE"
	exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	-n | --namespace)
		NAMESPACE="$2"
		shift 2
		;;
	-p | --profile)
		PROFILE="$2"
		shift 2
		;;
	-s | --scan-name)
		SCAN_NAME="$2"
		shift 2
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
# MAIN
# ============================================================================

log_info "Creating ScanSettingBinding..."
log_info "  Namespace: $NAMESPACE"
log_info "  Profile: $PROFILE"
log_info "  Scan Name: $SCAN_NAME"

if [[ "$DRY_RUN" == "true" ]]; then
	log_info "[DRY-RUN] Would apply the following ScanSettingBinding:"
	echo "---"
fi

# Create a ScanSettingBinding YAML
YAML_CONTENT=$(
	cat <<EOF
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: $SCAN_NAME
  namespace: $NAMESPACE
profiles:
- apiGroup: compliance.openshift.io/v1alpha1
  kind: Profile
  name: $PROFILE
  namespace: $NAMESPACE
settingsRef:
  apiGroup: compliance.openshift.io/v1alpha1
  kind: ScanSetting
  name: default
EOF
)

if [[ "$DRY_RUN" == "true" ]]; then
	echo "$YAML_CONTENT"
	echo "---"
	echo "$YAML_CONTENT" | oc apply --dry-run=server -f -
	log_info "[DRY-RUN] Validation passed. Run without --dry-run to apply."
else
	echo "$YAML_CONTENT" | oc apply -f -
	log_success "ScanSettingBinding '$SCAN_NAME' created in namespace '$NAMESPACE'."
	echo ""
	log_info "Check the scan status with:"
	echo "  oc get compliancescan -n $NAMESPACE"
fi
