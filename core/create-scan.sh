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
RECOMMENDED=false

# Recommended profiles for broad compliance coverage
RECOMMENDED_PROFILES=("ocp4-cis" "ocp4-moderate" "ocp4-pci-dss" "rhcos4-moderate")

usage() {
	echo "Usage: $0 [OPTIONS]"
	echo ""
	echo "Create a compliance scan using ScanSettingBinding."
	echo ""
	echo "Options:"
	echo "  -n, --namespace    Namespace for the scan (default: $NAMESPACE)"
	echo "  -p, --profile      Profile to scan against (default: $PROFILE)"
	echo "  -s, --scan-name    Name of the scan (default: $SCAN_NAME)"
	echo "  --recommended      Scan all 4 recommended profiles (CIS, Moderate, PCI-DSS)"
	echo "  --dry-run          Preview changes without applying"
	echo "  -h, --help         Show this help message"
	echo ""
	echo "Recommended profiles (used with --recommended):"
	echo "  ocp4-cis            CIS Benchmark (platform)"
	echo "  ocp4-moderate       NIST 800-53 Moderate (platform)"
	echo "  ocp4-pci-dss        PCI-DSS (platform)"
	echo "  rhcos4-moderate     NIST 800-53 Moderate (node)"
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
	--recommended)
		RECOMMENDED=true
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
# HELPER: create a single ScanSettingBinding
# ============================================================================

create_scan_binding() {
	local scan_name="$1"
	local profile="$2"

	local yaml_content
	yaml_content=$(
		cat <<EOYAML
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: ${scan_name}
  namespace: ${NAMESPACE}
profiles:
- apiGroup: compliance.openshift.io/v1alpha1
  kind: Profile
  name: ${profile}
  namespace: ${NAMESPACE}
settingsRef:
  apiGroup: compliance.openshift.io/v1alpha1
  kind: ScanSetting
  name: default
EOYAML
	)

	if [[ "$DRY_RUN" == "true" ]]; then
		echo "---"
		echo "$yaml_content"
		echo "$yaml_content" | oc apply --dry-run=server -f -
	else
		echo "$yaml_content" | oc apply -f -
	fi
}

# ============================================================================
# MAIN
# ============================================================================

if [[ "$RECOMMENDED" == "true" ]]; then
	log_info "Creating scans for all recommended profiles..."
	log_info "  Namespace: $NAMESPACE"
	log_info "  Profiles: ${RECOMMENDED_PROFILES[*]}"

	for profile in "${RECOMMENDED_PROFILES[@]}"; do
		scan_name="${profile}-scan"
		log_info "  Creating scan: $scan_name (profile: $profile)"
		create_scan_binding "$scan_name" "$profile"
	done

	if [[ "$DRY_RUN" == "true" ]]; then
		log_info "[DRY-RUN] Validation passed. Run without --dry-run to apply."
	else
		log_success "All recommended scans created in namespace '$NAMESPACE'."
		echo ""
		log_info "Scans created:"
		for profile in "${RECOMMENDED_PROFILES[@]}"; do
			echo "       - ${profile}-scan ($profile)"
		done
		echo ""
		log_info "Check the scan status with:"
		echo "  oc get compliancescan -n $NAMESPACE"
	fi
else
	log_info "Creating ScanSettingBinding..."
	log_info "  Namespace: $NAMESPACE"
	log_info "  Profile: $PROFILE"
	log_info "  Scan Name: $SCAN_NAME"

	create_scan_binding "$SCAN_NAME" "$PROFILE"

	if [[ "$DRY_RUN" == "true" ]]; then
		log_info "[DRY-RUN] Validation passed. Run without --dry-run to apply."
	else
		log_success "ScanSettingBinding '$SCAN_NAME' created in namespace '$NAMESPACE'."
		echo ""
		log_info "Check the scan status with:"
		echo "  oc get compliancescan -n $NAMESPACE"
	fi
fi
