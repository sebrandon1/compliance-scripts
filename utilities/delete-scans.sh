#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Remove periodic Compliance Operator scans and related ScanSettings.
# Defaults to namespace 'openshift-compliance'.
# By default this removes:
#   - ComplianceSuite/ScanSettingBinding: periodic-e8
#   - ScanSetting: periodic-setting (and tiny-setting if present)
#   - PVCs created by the periodic bindings (best-effort)
# Optionally, pass --include-cis to also remove the cis-scan binding/suite and its PVC.

NAMESPACE="$DEFAULT_COMPLIANCE_NAMESPACE"
INCLUDE_CIS=false

usage() {
	cat <<USAGE
Usage: $(basename "$0") [--namespace NAMESPACE] [--include-cis]

Remove periodic scans and scan settings in the Compliance Operator namespace.

Options:
  -n, --namespace NAMESPACE   Target namespace (default: ${NAMESPACE})
  --include-cis               Also remove the 'cis-scan' binding/suite and PVC
  -h, --help                  Show this help and exit
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-n | --namespace)
		NAMESPACE="$2"
		shift 2
		;;
	--include-cis)
		INCLUDE_CIS=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		shift
		;;
	esac
done

log_info "Deleting periodic resources in namespace '$NAMESPACE'"

PERIODIC_BINDING="scansettingbinding/periodic-e8"
PERIODIC_SUITE="compliancesuite/periodic-e8"
PERIODIC_SETTING="scansetting/periodic-setting"
TINY_SETTING="scansetting/tiny-setting"

remove_finalizers_from_kind "compliancescans.compliance.openshift.io" "$NAMESPACE"
remove_finalizers_from_kind "compliancesuites.compliance.openshift.io" "$NAMESPACE"

# Delete periodic suite and binding (best-effort)
oc delete $PERIODIC_SUITE -n "$NAMESPACE" --ignore-not-found=true || true
oc delete $PERIODIC_BINDING -n "$NAMESPACE" --ignore-not-found=true || true

# Delete ScanSettings (best-effort)
oc delete $PERIODIC_SETTING -n "$NAMESPACE" --ignore-not-found=true || true
oc delete $TINY_SETTING -n "$NAMESPACE" --ignore-not-found=true || true

# Delete PVCs commonly created by periodic scans (best-effort)
oc -n "$NAMESPACE" delete pvc ocp4-e8 rhcos4-e8-master rhcos4-e8-worker --ignore-not-found=true || true

if [[ "$INCLUDE_CIS" == true ]]; then
	log_info "Also removing 'cis-scan' resources"
	remove_finalizers_from_kind "compliancescans.compliance.openshift.io" "$NAMESPACE"
	remove_finalizers_from_kind "compliancesuites.compliance.openshift.io" "$NAMESPACE"

	# Delete cis binding/suite (best-effort)
	oc delete scansettingbinding/cis-scan -n "$NAMESPACE" --ignore-not-found=true || true
	oc delete compliancesuite/cis-scan -n "$NAMESPACE" --ignore-not-found=true || true

	# PVC created for cis resultserver
	oc -n "$NAMESPACE" delete pvc ocp4-cis --ignore-not-found=true || true
fi

# Cleanup any remaining resultserver pods pending due to PVCs (best-effort)
oc -n "$NAMESPACE" delete pod -l workload=resultserver --ignore-not-found=true >/dev/null 2>&1 || true

log_success "Periodic scan resources removal initiated. Some deletions may complete asynchronously."
