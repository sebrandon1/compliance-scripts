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
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
load_env

# Check required dependencies
require_cmd oc yq jq

# Check cluster connectivity
require_cluster

# Defaults (can be overridden by .env or CLI flags)
NAMESPACE=$(get_compliance_namespace)
DESTINATION_DIR="${REMEDIATION_DIR:-complianceremediations}"
SEVERITY_FILTER="${SEVERITY_FILTER:-}"
CLEAN_OUTPUT=0

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
		if [[ "$NAMESPACE" == "$DEFAULT_COMPLIANCE_NAMESPACE" ]]; then
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

# Fetch all complianceremediation objects as JSON (single parse, O(n) extraction)
log_info "Fetching complianceremediation objects from cluster..."
REMEDIATION_JSON=$(oc get complianceremediation -n "$NAMESPACE" -o json)

# Build a name->severity associative array from ComplianceCheckResult
declare -A severity_map
while read -r sname ssev; do
	severity_map["$sname"]="$ssev"
done < <(oc get compliancecheckresult -A | awk 'NR>1 {print tolower($2), tolower($4)}')

# Split all items into individual JSON files in one pass
ITEMS_DIR=$(make_temp_dir)
while IFS= read -r item; do
	item_name=$(echo "$item" | jq -r '.metadata.name')
	echo "$item" >"$ITEMS_DIR/$item_name.json"
done < <(echo "$REMEDIATION_JSON" | jq -c '.items[]')

# Counters for logging
count_total=0
count_valid=0
count_invalid=0
count_skipped_severity=0
kinds=()

for item_file in "$ITEMS_DIR"/*.json; do
	[[ -f "$item_file" ]] || continue
	name=$(basename "$item_file" .json)
	count_total=$((count_total + 1))

	# Apply severity filter if requested
	check_severity="${severity_map[$name]:-}"
	if [[ ${#severity_list[@]} -gt 0 ]]; then
		allowed=0
		for s in "${severity_list[@]}"; do
			if [[ "$check_severity" == "$s" ]]; then
				allowed=1
				break
			fi
		done
		if [[ $allowed -eq 0 ]]; then
			count_skipped_severity=$((count_skipped_severity + 1))
			continue
		fi
	fi

	# Extract spec.current.object as raw YAML
	spec_object=$(jq -r '.spec.current.object' "$item_file") || true

	if [[ -z "$spec_object" ]] || ! echo "$spec_object" | yq e '.' - >/dev/null 2>&1; then
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
print_summary \
	"Total processed" "$count_total" \
	"Valid collected" "$count_valid" \
	"Invalid skipped" "$count_invalid" \
	"Severity filtered" "$count_skipped_severity" \
	"Output directory" "$DESTINATION_DIR"

echo ""
log_info "Kinds found in collected objects:"
echo "$unique_kinds"

if [[ "$DRY_RUN" == "true" ]]; then
	log_info "[DRY-RUN] No files were written. Run without --dry-run to collect."
else
	log_success "All complianceremediation objects have been saved to the $DESTINATION_DIR directory."
fi
