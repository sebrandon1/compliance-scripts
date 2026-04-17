#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

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
	log_error "Invalid severity: $SEVERITY"
	usage
	;;
	# no default
esac

require_cmd oc yq
require_cluster

NAMESPACE="$DEFAULT_COMPLIANCE_NAMESPACE"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$REPO_DIR/complianceremediations"

log_info "Applying combined remediation YAMLs (no ComplianceRemediation patching)."

if [[ ! -d "$SRC_DIR" ]]; then
	log_warn "Source directory not found: $SRC_DIR"
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
	log_warn "No remediation YAMLs found for severity '$SEVERITY' under $SRC_DIR."
	exit 0
fi

COUNT=$(printf "%s\n" "$FILES_TO_APPLY" | grep -c ".")
log_info "Applying $COUNT remediation YAML(s) for severity '$SEVERITY'..."

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
		role=$(get_node_role "$file")
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
		log_warn "Transformed YAML is invalid for $file. Skipping."
		echo "$file,invalid-transformed-yaml" >>"$report_path"
		continue
	fi

	# Server-side dry-run first
	log_info "[DRY-RUN] oc apply --dry-run=server -f $modified_file"
	oc apply --dry-run=server -f "$modified_file"

	log_info "[APPLY] oc apply -f $modified_file (from $file) | reboot_hint=$reboot_hint"
	result=$(oc apply -f "$modified_file" 2>&1 || true)
	echo "$result"
	echo "$file,$reboot_hint,${result//,/;}" >>"$report_path"

	# Wait for reconciliation where appropriate
	if [[ "$kind" == "MachineConfig" ]]; then
		log_info "Waiting for MCP/$role to become Updated=True"
		oc wait mcp/"$role" --for=condition=Updated=True --timeout=45m
		oc get mcp "$role" -o wide || true
	elif [[ "$kind" == "APIServer" ]]; then
		log_info "Waiting for kube-apiserver operator Available=True"
		oc wait co/kube-apiserver --for=condition=Available=True --timeout=10m || true
	else
		# Basic existence check for other resource kinds
		oc get -f "$modified_file" >/dev/null 2>&1 || true
	fi
done <<<"$FILES_TO_APPLY"

log_success "Completed applying remediations for severity '$SEVERITY'."
log_info "Wrote YAML apply report to $report_path"
