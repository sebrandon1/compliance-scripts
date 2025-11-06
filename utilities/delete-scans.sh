#!/bin/bash
set -euo pipefail

# Remove periodic Compliance Operator scans and related ScanSettings.
# Defaults to namespace 'openshift-compliance'.
# By default this removes:
#   - ComplianceSuite/ScanSettingBinding: periodic-e8
#   - ScanSetting: periodic-setting (and tiny-setting if present)
#   - PVCs created by the periodic bindings (best-effort)
# Optionally, pass --include-cis to also remove the cis-scan binding/suite and its PVC.

NAMESPACE="openshift-compliance"
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

echo "[INFO] Deleting periodic resources in namespace '$NAMESPACE'"

# Best-effort: remove finalizers from suites/scans so deletion does not hang
remove_finalizers() {
	local kind="$1"
	local selector="$2"
	local names
	names=$(oc get "$kind" -n "$NAMESPACE" -l "$selector" -o name 2>/dev/null || true)
	if [[ -z "$names" ]]; then return 0; fi
	echo "$names" | while read -r res; do
		[[ -z "$res" ]] && continue
		oc patch "$res" -n "$NAMESPACE" --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
	done
}

# Identify known objects
PERIODIC_BINDING="scansettingbinding/periodic-e8"
PERIODIC_SUITE="compliancesuite/periodic-e8"
PERIODIC_SETTING="scansetting/periodic-setting"
TINY_SETTING="scansetting/tiny-setting"

# Clear finalizers on periodic suite/scans (best-effort)
remove_finalizers compliancescans.compliance.openshift.io 'compliance.openshift.io/suite=periodic-e8'
remove_finalizers compliancesuites.compliance.openshift.io 'metadata.name=periodic-e8'

# Delete periodic suite and binding (best-effort)
oc delete $PERIODIC_SUITE -n "$NAMESPACE" --ignore-not-found=true || true
oc delete $PERIODIC_BINDING -n "$NAMESPACE" --ignore-not-found=true || true

# Delete ScanSettings (best-effort)
oc delete $PERIODIC_SETTING -n "$NAMESPACE" --ignore-not-found=true || true
oc delete $TINY_SETTING -n "$NAMESPACE" --ignore-not-found=true || true

# Delete PVCs commonly created by periodic scans (best-effort)
oc -n "$NAMESPACE" delete pvc ocp4-e8 rhcos4-e8-master rhcos4-e8-worker --ignore-not-found=true || true

if [[ "$INCLUDE_CIS" == true ]]; then
	echo "[INFO] Also removing 'cis-scan' resources"
	# Clear finalizers for cis suite/scans
	remove_finalizers compliancescans.compliance.openshift.io 'compliance.openshift.io/scan-name=ocp4-cis'
	remove_finalizers compliancesuites.compliance.openshift.io 'metadata.name=cis-scan'

	# Delete cis binding/suite (best-effort)
	oc delete scansettingbinding/cis-scan -n "$NAMESPACE" --ignore-not-found=true || true
	oc delete compliancesuite/cis-scan -n "$NAMESPACE" --ignore-not-found=true || true

	# PVC created for cis resultserver
	oc -n "$NAMESPACE" delete pvc ocp4-cis --ignore-not-found=true || true
fi

# Cleanup any remaining resultserver pods pending due to PVCs (best-effort)
oc -n "$NAMESPACE" delete pod -l workload=resultserver --ignore-not-found=true >/dev/null 2>&1 || true

echo "[SUCCESS] Periodic scan resources removal initiated. Some deletions may complete asynchronously."
