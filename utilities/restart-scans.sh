#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

NAMESPACE="$DEFAULT_COMPLIANCE_NAMESPACE"
WATCH=false
ALL=false
declare -a SCANS

usage() {
	cat <<USAGE
Usage: $0 [--namespace NAMESPACE|-n NAMESPACE] [--watch] [--scan NAME [--scan NAME ...] | NAME [NAME ...]]

Defaults to restarting all scans if no specific scans are provided.

Examples:
  $0                                    # Restart all scans
  $0 ocp4-cis rhcos4-e8-worker          # Restart specific scans
  $0 -n openshift-compliance --watch    # Restart all scans and watch
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-n | --namespace)
		NAMESPACE="$2"
		shift 2
		;;
	--watch)
		WATCH=true
		shift
		;;
	--all)
		ALL=true
		shift
		;;
	--scan)
		SCANS+=("$2")
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	--)
		shift
		break
		;;
	-*)
		log_error "Unknown flag: $1"
		usage
		exit 1
		;;
	*)
		SCANS+=("$1")
		shift
		;;
	esac
done

# Default to ALL if no specific scans provided
if [[ "${#SCANS[@]}" -eq 0 ]]; then
	ALL=true
fi

log_info "Verifying namespace '$NAMESPACE' exists..."
if ! oc get ns "$NAMESPACE" &>/dev/null; then
	log_error "Namespace '$NAMESPACE' not found. Ensure you're connected to an OpenShift cluster."
	exit 1
fi

if [[ "$ALL" == true ]]; then
	log_info "Restarting all ComplianceScans in namespace '$NAMESPACE'..."
	SCANS_OUTPUT=$(oc -n "$NAMESPACE" get compliancescan -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
	SCANS=()
	if [[ -n "$SCANS_OUTPUT" ]]; then
		while IFS= read -r name; do
			[[ -n "$name" ]] && SCANS+=("$name")
		done <<<"$SCANS_OUTPUT"
	fi
	if [[ "${#SCANS[@]}" -eq 0 ]]; then
		log_warn "No ComplianceScans found in '$NAMESPACE'. Nothing to restart."
		exit 0
	fi
fi

log_info "Requesting rescan for ${#SCANS[@]} scan(s) in '$NAMESPACE'..."
for scan in "${SCANS[@]}"; do
	if ! oc -n "$NAMESPACE" get compliancescan "$scan" &>/dev/null; then
		log_warn "ComplianceScan '$scan' not found in namespace '$NAMESPACE'; skipping."
		continue
	fi
	log_info "Annotating 'compliancescan/$scan' with compliance.openshift.io/rescan="
	oc -n "$NAMESPACE" annotate "compliancescan/$scan" compliance.openshift.io/rescan= --overwrite=true
done

if [[ "$WATCH" == true ]]; then
	log_info "Watching ComplianceScans in '$NAMESPACE'... (Ctrl+C to exit)"
	oc -n "$NAMESPACE" get compliancescan -w | cat
else
	log_info "Current ComplianceScan statuses:"
	oc -n "$NAMESPACE" get compliancescan | cat
fi

log_success "Rescan requests submitted."
