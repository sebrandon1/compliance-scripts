#!/bin/bash
# apply-periodic-scan.sh - Set up recurring daily compliance scans
#
# Creates a custom "periodic-setting" ScanSetting with a daily cron schedule
# (0 1 * * *), PVC-backed raw result storage, and node tolerations. Then
# creates ScanSettingBindings for four profile groups:
#   - E8        (rhcos4-e8, ocp4-e8)
#   - CIS       (ocp4-cis)
#   - Moderate  (ocp4-moderate, rhcos4-moderate)
#   - PCI-DSS   (ocp4-pci-dss)
#
# For a one-time on-demand scan using the built-in "default" ScanSetting,
# use create-scan.sh instead.
#
# Usage: ./core/apply-periodic-scan.sh [OPTIONS]
#
# Options:
#   -n, --namespace    Namespace for the scan (default: openshift-compliance)
#   -t, --platform     Platform filter: ocp, rhcos, or all (default: all)
#   --no-pvc           Skip PVC configuration for rawResultStorage
#   --dry-run          Preview changes without applying
#   -h, --help         Show this help message

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
load_env

# Defaults (can be overridden by .env or CLI flags)
NAMESPACE=$(get_compliance_namespace)
NO_PVC="${NO_PVC:-false}"
PLATFORM="${PLATFORM:-all}"

usage() {
	echo "Usage: $0 [OPTIONS]"
	echo ""
	echo "Apply periodic compliance scan configuration (CIS, NIST Moderate, PCI-DSS profiles)."
	echo ""
	echo "Options:"
	echo "  -n, --namespace    Namespace for the scan (default: $NAMESPACE)"
	echo "  -t, --platform     Platform filter: ocp, rhcos, or all (default: all)"
	echo "  --no-pvc           Skip PVC configuration for rawResultStorage"
	echo "  --dry-run          Preview changes without applying"
	echo "  -h, --help         Show this help message"
	echo ""
	echo "Platform filters:"
	echo "  ocp     OCP platform checks only (ocp4-* profiles)"
	echo "  rhcos   RHCOS node checks only (rhcos4-* profiles)"
	echo "  all     Both platforms (default)"
	echo ""
	echo "Environment variables: COMPLIANCE_NAMESPACE, NO_PVC, PLATFORM, SC_NAME, RAW_SIZE, ROTATION"
	exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	-n | --namespace)
		NAMESPACE="$2"
		shift 2
		;;
	-t | --platform)
		PLATFORM="$2"
		if [[ "$PLATFORM" != "ocp" && "$PLATFORM" != "rhcos" && "$PLATFORM" != "all" ]]; then
			log_error "Invalid platform: $PLATFORM (must be ocp, rhcos, or all)"
			exit 1
		fi
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
		SC_NAME=$(get_default_storage_class)
	fi
	# Storage defaults aligned with CRD defaults
	RAW_SIZE="${RAW_SIZE:-1Gi}"
	ROTATION="${ROTATION:-3}"
fi

# ============================================================================
# MAIN
# ============================================================================

# ============================================================================
# SNO DETECTION
# ============================================================================
NODE_COUNT=$(oc get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$NODE_COUNT" -eq 1 ]]; then
	IS_SNO=true
	SCAN_ROLES="worker"
	log_info "Detected Single Node OpenShift (SNO) - using worker role only"
else
	IS_SNO=false
	SCAN_ROLES="worker master"
fi

log_info "Applying periodic scan configuration..."
log_info "  Namespace: $NAMESPACE"
log_info "  Platform: $PLATFORM"
log_info "  Topology: $([ "$IS_SNO" == "true" ] && echo "SNO (1 node)" || echo "Multi-node ($NODE_COUNT nodes)")"
log_info "  Scan roles: $SCAN_ROLES"
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
$(for role in $SCAN_ROLES; do echo "  - $role"; done)
EOF
)

# ============================================================================
# HELPER: generate a ScanSettingBinding YAML for one or more profiles
# ============================================================================

gen_scan_binding() {
	local name="$1"
	shift
	local profiles_yaml=""
	for profile in "$@"; do
		profiles_yaml+="  - name: ${profile}
    kind: Profile
    apiGroup: compliance.openshift.io/v1alpha1
"
	done
	cat <<EOF
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: ${name}
  namespace: ${NAMESPACE}
profiles:
${profiles_yaml}settingsRef:
  name: periodic-setting
  kind: ScanSetting
  apiGroup: compliance.openshift.io/v1alpha1
EOF
}

# Check profile availability
E8_AVAILABLE=false
if profile_exists "ocp4-e8" "$NAMESPACE" && profile_exists "rhcos4-e8" "$NAMESPACE"; then
	E8_AVAILABLE=true
else
	log_warn "E8 profiles not available on this cluster, skipping periodic-e8 binding"
fi

# Determine profiles per binding based on platform
case "$PLATFORM" in
all) E8_PROFILES=("rhcos4-e8" "ocp4-e8") MOD_PROFILES=("ocp4-moderate" "rhcos4-moderate") ;;
ocp) E8_PROFILES=("ocp4-e8") MOD_PROFILES=("ocp4-moderate") ;;
rhcos) E8_PROFILES=("rhcos4-e8") MOD_PROFILES=("rhcos4-moderate") ;;
esac

echo "$SCANSETTING_YAML" | apply_inline

BINDINGS_CREATED=()

if [[ "$E8_AVAILABLE" == "true" ]]; then
	gen_scan_binding "periodic-e8" "${E8_PROFILES[@]}" | apply_inline
	BINDINGS_CREATED+=("periodic-e8 (${E8_PROFILES[*]})")
fi

if [[ "$PLATFORM" != "rhcos" ]]; then
	gen_scan_binding "cis-scan" "ocp4-cis" | apply_inline
	BINDINGS_CREATED+=("cis-scan (ocp4-cis)")
fi

gen_scan_binding "periodic-moderate" "${MOD_PROFILES[@]}" | apply_inline
BINDINGS_CREATED+=("periodic-moderate (${MOD_PROFILES[*]})")

if [[ "$PLATFORM" != "rhcos" ]]; then
	gen_scan_binding "periodic-pci-dss" "ocp4-pci-dss" | apply_inline
	BINDINGS_CREATED+=("periodic-pci-dss (ocp4-pci-dss)")
fi

if [[ "$DRY_RUN" != "true" ]]; then
	log_success "ScanSetting 'periodic-setting' applied in namespace '$NAMESPACE'."
	log_info "ScanSettingBindings created:"
	for binding in "${BINDINGS_CREATED[@]}"; do
		echo "       - $binding"
	done
	echo ""
	log_info "To create an on-demand scan, run: ./core/create-scan.sh"
fi
