#!/bin/bash
# collect-complianceremediations.sh - Collect compliance remediation data from cluster
#
# Usage: ./core/collect-complianceremediations.sh [OPTIONS]
#
# Options:
#   -n, --namespace    Namespace for complianceremediation objects (default: openshift-compliance)
#   -s, --severity     Comma-separated severities to include: high,medium,low
#   -f, --fresh        Remove existing output directory before collecting
#   --dry-run          Show what would be collected without writing files
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
	log_warn() { echo "[WARN] $*"; }
	log_error() { echo "[ERROR] $*" >&2; }
	log_success() { echo "[SUCCESS] $*"; }
	require_cmd() { for cmd in "$@"; do command -v "$cmd" &>/dev/null || {
		echo "Error: '$cmd' not found"
		exit 1
	}; done; }
	require_cluster() { oc whoami &>/dev/null || {
		echo "Error: Not connected to cluster"
		exit 1
	}; }
	print_summary() {
		echo "Summary:"
		while [[ $# -ge 2 ]]; do
			echo "  $1: $2"
			shift 2
		done
	}
fi

# Check required dependencies
require_cmd oc yq

# Check cluster connectivity
require_cluster

# Defaults (can be overridden by .env or CLI flags)
NAMESPACE="${COMPLIANCE_NAMESPACE:-openshift-compliance}"
DESTINATION_DIR="${REMEDIATION_DIR:-complianceremediations}"
SEVERITY_FILTER="${SEVERITY_FILTER:-}"
CLEAN_OUTPUT=0
DRY_RUN="${DRY_RUN:-false}"

usage() {
	echo "Usage: $0 [OPTIONS]"
	echo ""
	echo "Collect compliance remediation data from the cluster."
	echo ""
	echo "Options:"
	echo "  -n, --namespace   Namespace for complianceremediation objects (default: $NAMESPACE)"
	echo "  -s, --severity    Comma-separated severities to include: high,medium,low (case-insensitive)"
	echo "  -f, --fresh       Remove existing output directory before collecting"
	echo "  --dry-run         Show what would be collected without writing files"
	echo "  -h, --help        Show this help message"
	echo ""
	echo "Environment variables: COMPLIANCE_NAMESPACE, REMEDIATION_DIR, SEVERITY_FILTER"
	exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	-n | --namespace)
		NAMESPACE="$2"
		shift 2
		;;
	-s | --severity)
		SEVERITY_FILTER="$2"
		shift 2
		;;
	-f | --fresh)
		CLEAN_OUTPUT=1
		shift
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	-h | --help)
		usage
		;;
	--)
		shift
		break
		;;
	-*)
		log_error "Unknown option: $1"
		usage
		;;
	*)
		# Backward compatibility: treat first non-flag arg as namespace if not set explicitly
		if [[ "$NAMESPACE" == "openshift-compliance" ]]; then
			NAMESPACE="$1"
			shift
			continue
		fi
		log_error "Unexpected argument: $1"
		usage
		;;
	esac
done

log_info "Collecting compliance remediations..."
log_info "  Namespace: $NAMESPACE"
log_info "  Output directory: $DESTINATION_DIR"

if [[ "$DRY_RUN" == "true" ]]; then
	log_info "[DRY-RUN] Will show what would be collected without writing files"
fi

# Prepare output directory
if [[ "$DRY_RUN" != "true" ]]; then
	if [[ $CLEAN_OUTPUT -eq 1 ]]; then
		log_info "Removing existing $DESTINATION_DIR directory to start fresh."
		rm -rf "$DESTINATION_DIR"
	fi
	mkdir -p "$DESTINATION_DIR"
fi

# Normalize and validate severity filter if provided
declare -a severity_list=()
if [[ -n "$SEVERITY_FILTER" ]]; then
	SEVERITY_FILTER=$(echo "$SEVERITY_FILTER" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
	IFS=',' read -r -a severity_list <<<"$SEVERITY_FILTER"
	for s in "${severity_list[@]}"; do
		if [[ "$s" != "high" && "$s" != "medium" && "$s" != "low" ]]; then
			log_error "Invalid severity '$s'. Allowed values: high, medium, low"
			exit 1
		fi
	done
	log_info "Severity filter enabled: $SEVERITY_FILTER"
	# Create subdirectories for each requested severity under the destination directory
	if [[ "$DRY_RUN" != "true" ]]; then
		for s in "${severity_list[@]}"; do
			mkdir -p "$DESTINATION_DIR/$s"
		done
	fi
fi

# Fetch all complianceremediation objects in YAML format
log_info "Fetching complianceremediation objects from cluster..."
complianceremediations=$(oc get complianceremediation -n "$NAMESPACE" -o yaml)

# Build a name->severity map from ComplianceCheckResult (names should match remediation names)
severity_lines=$(oc get compliancecheckresult -A | awk 'NR>1 {print $2, $4}')
# Lowercase entire mapping to ease comparisons
severity_lines=$(echo "$severity_lines" | tr '[:upper:]' '[:lower:]')

# Extract the names of the complianceremediation objects
names=$(echo "$complianceremediations" | yq e '.items[].metadata.name' -)

# Counters for logging
count_total=0
count_valid=0
count_invalid=0
count_skipped_severity=0
kinds=()

# Loop through each complianceremediation object
for name in $names; do
	count_total=$((count_total + 1))

	# Apply severity filter if requested
	check_severity=$(echo "$severity_lines" | awk -v n="$name" '$1==n{print $2; exit}')
	if [[ ${#severity_list[@]} -gt 0 ]]; then
		allowed=0
		for s in "${severity_list[@]}"; do
			if [[ "$check_severity" == "$s" ]]; then
				allowed=1
				break
			fi
		done
		if [[ $allowed -eq 0 ]]; then
			# Skip this remediation due to severity filter
			count_skipped_severity=$((count_skipped_severity + 1))
			continue
		fi
	fi

	# Extract the spec.object YAML structure for the current object
	spec_object=$(echo "$complianceremediations" | yq e ".items[] | select(.metadata.name == \"$name\") | .spec.current.object" -)

	# Validate the YAML structure of the spec.object
	if ! echo "$spec_object" | yq e '.' - >/dev/null 2>&1; then
		log_warn "Invalid YAML for complianceremediation object '$name'. Skipping."
		count_invalid=$((count_invalid + 1))
		continue
	fi

	# Determine output directory (severity subfolder if filter specified)
	output_dir="$DESTINATION_DIR"
	if [[ ${#severity_list[@]} -gt 0 && -n "$check_severity" ]]; then
		output_dir="$DESTINATION_DIR/$check_severity"
	fi

	# Extract kind if possible
	kind=$(echo "$spec_object" | yq e '.kind' - 2>/dev/null || true)
	if [[ -n "$kind" && "$kind" != "null" ]]; then
		kinds+=("$kind")
	fi

	if [[ "$DRY_RUN" == "true" ]]; then
		log_info "[DRY-RUN] Would collect: $name ($kind) -> $output_dir/$name.yaml"
	else
		mkdir -p "$output_dir"
		echo "$spec_object" >"$output_dir/$name.yaml"
	fi
	count_valid=$((count_valid + 1))
done

# Build unique kinds summary
if [[ ${#kinds[@]} -gt 0 ]]; then
	unique_kinds=$(printf "%s\n" "${kinds[@]}" | sort | uniq -c | sort -nr)
else
	unique_kinds="(none)"
fi

# Print summary
if type print_summary &>/dev/null; then
	print_summary \
		"Total processed" "$count_total" \
		"Valid collected" "$count_valid" \
		"Invalid skipped" "$count_invalid" \
		"Severity filtered" "$count_skipped_severity" \
		"Output directory" "$DESTINATION_DIR"
else
	echo -e "\n[SUMMARY]"
	echo "Total complianceremediation objects processed: $count_total"
	echo "Valid YAMLs collected: $count_valid"
	echo "Invalid YAMLs skipped: $count_invalid"
	if [[ -n "$SEVERITY_FILTER" ]]; then
		echo "Skipped due to severity filter ($SEVERITY_FILTER): $count_skipped_severity"
	fi
fi

echo ""
log_info "Kinds found in collected objects:"
echo "$unique_kinds"

if [[ "$DRY_RUN" == "true" ]]; then
	log_info "[DRY-RUN] No files were written. Run without --dry-run to collect."
else
	log_success "All complianceremediation objects have been saved to the $DESTINATION_DIR directory."
fi
