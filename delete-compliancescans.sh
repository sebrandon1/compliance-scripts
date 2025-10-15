#!/bin/bash
set -euo pipefail

NAMESPACE="openshift-compliance"
FILTER=""
DELETE_SUITE=false
DELETE_SSB=false

usage() {
	echo "Usage: $0 [-n|--namespace NAMESPACE] [--filter SUBSTRING] [--delete-suite] [--delete-ssb]"
	echo "\nOptions:"
	echo "  -n, --namespace     Target namespace (default: openshift-compliance)"
	echo "      --filter        Only delete scans whose name contains this substring"
	echo "      --delete-suite  Also delete related ComplianceSuite(s)"
	echo "      --delete-ssb    Also delete ScanSettingBinding(s) matching suite name(s)"
	echo "  -h, --help          Show this help"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-n | --namespace)
		NAMESPACE="$2"
		shift 2
		;;
	--filter)
		FILTER="$2"
		shift 2
		;;
	--delete-suite)
		DELETE_SUITE=true
		shift
		;;
	--delete-ssb)
		DELETE_SSB=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "[ERROR] Unknown argument: $1"
		usage
		exit 1
		;;
	esac
done

echo "[INFO] Deleting ComplianceScan objects in namespace '$NAMESPACE'"

# Gather scans, optionally filter by substring
SCANS=$(oc get compliancescan -n "$NAMESPACE" -o name 2>/dev/null || true)
if [[ -n "$FILTER" && -n "$SCANS" ]]; then
	SCANS=$(echo "$SCANS" | grep "$FILTER" || true)
fi

if [[ -z "$SCANS" ]]; then
	echo "[INFO] No ComplianceScan objects found to delete."
	exit 0
fi

echo "[INFO] Target scans:"
echo "$SCANS" | sed 's/^/\t- /'

# Optionally find related ComplianceSuite names via ownerReferences
SUITES=""
if [[ "$DELETE_SUITE" == true || "$DELETE_SSB" == true ]]; then
	for scan in $SCANS; do
		SUITE_NAME=$(oc get "$scan" -n "$NAMESPACE" -o jsonpath='{range .metadata.ownerReferences[?(@.kind=="ComplianceSuite")]}{.name}{end}' 2>/dev/null || true)
		if [[ -n "$SUITE_NAME" ]]; then
			SUITES+="$SUITE_NAME\n"
		fi
	done
	# Deduplicate suite names
	if [[ -n "$SUITES" ]]; then
		SUITES=$(echo -e "$SUITES" | sort -u)
	fi
fi

# Delete scans first
echo "[INFO] Deleting ComplianceScan objects..."
oc delete $SCANS -n "$NAMESPACE" --ignore-not-found=true

# Optionally delete related suites to prevent immediate recreation
if [[ "$DELETE_SUITE" == true && -n "$SUITES" ]]; then
	echo "[INFO] Deleting related ComplianceSuite objects:"
	echo "$SUITES" | sed 's/^/\t- /'
	for s in $SUITES; do
		oc delete compliancesuite "$s" -n "$NAMESPACE" --ignore-not-found=true || true
	done
fi

# Optionally delete SSBs matching suite names (create-scan.sh uses SSB name as scan binding)
if [[ "$DELETE_SSB" == true && -n "$SUITES" ]]; then
	echo "[INFO] Deleting ScanSettingBinding objects matching suite names:"
	echo "$SUITES" | sed 's/^/\t- /'
	for s in $SUITES; do
		oc delete scansettingbinding "$s" -n "$NAMESPACE" --ignore-not-found=true || true
	done
fi

# Wait for scans to be gone (best-effort)
echo "[INFO] Waiting for ComplianceScan objects to be deleted..."
for i in {1..30}; do
	REMAINING=$(oc get compliancescan -n "$NAMESPACE" -o name 2>/dev/null || true)
	if [[ -n "$FILTER" && -n "$REMAINING" ]]; then
		REMAINING=$(echo "$REMAINING" | grep "$FILTER" || true)
	fi
	if [[ -z "$REMAINING" ]]; then
		echo "[SUCCESS] ComplianceScan objects have been deleted."
		exit 0
	fi
	sleep 2
done

echo "[WARN] Some ComplianceScan objects may still remain or be re-created by a ComplianceSuite."
echo "[HINT] Re-run with --delete-suite to remove suites, or --delete-ssb to remove the binding."
exit 0
