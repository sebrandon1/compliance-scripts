#!/bin/bash
# export-compliance-data.sh
# Exports Compliance Operator check results to JSON for the GitHub Pages
# compliance dashboard (https://sebrandon1.github.io/compliance-scripts/).
#
# Prerequisites:
#   - Compliance scans must have completed on the connected cluster
#   - oc must be logged in (KUBECONFIG set to target cluster)
#
# Usage: ./core/export-compliance-data.sh <ocp-version>
# Example: ./core/export-compliance-data.sh 4.17
#
# Requires: oc, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
source "$REPO_ROOT/lib/common.sh"

NAMESPACE="${COMPLIANCE_NAMESPACE:-$DEFAULT_COMPLIANCE_NAMESPACE}"
OUTPUT_DIR="${REPO_ROOT}/docs/_data"
TRACKING_FILE="${OUTPUT_DIR}/tracking.json"

# Validate arguments
if [[ $# -lt 1 ]]; then
	log_error "OCP version required"
	echo "Usage: $0 <ocp-version>"
	echo "Example: $0 4.17"
	exit 1
fi

OCP_VERSION="$1"
# Replace dots with underscores for Jekyll compatibility
VERSION_SLUG="${OCP_VERSION//./_}"
OUTPUT_FILE="${OUTPUT_DIR}/ocp-${VERSION_SLUG}.json"

log_info "=== Compliance Data Export ==="
log_info "OCP Version: ${OCP_VERSION}"
log_info "Namespace: ${NAMESPACE}"
log_info "Output: ${OUTPUT_FILE}"

require_cmd oc jq
require_cluster

log_info "Cluster: connected"

# Get current timestamp
SCAN_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log_info "Collecting ComplianceCheckResults..."

# Collect all check results
CHECK_RESULTS=$(oc get compliancecheckresults -n "${NAMESPACE}" -o json 2>/dev/null)

if [[ -z "$CHECK_RESULTS" ]] || [[ "$(echo "$CHECK_RESULTS" | jq '.items | length')" -eq 0 ]]; then
	log_error "No ComplianceCheckResults found in namespace ${NAMESPACE}"
	exit 1
fi

TOTAL_CHECKS=$(echo "$CHECK_RESULTS" | jq '.items | length')
log_info "Found ${TOTAL_CHECKS} compliance checks"

# Count by status
# Note: .status is a string field (e.g., "PASS", "FAIL", "MANUAL"), not an object
PASSING=$(echo "$CHECK_RESULTS" | jq '[.items[] | select(.status == "PASS")] | length')
FAILING=$(echo "$CHECK_RESULTS" | jq '[.items[] | select(.status == "FAIL")] | length')
MANUAL=$(echo "$CHECK_RESULTS" | jq '[.items[] | select(.status == "MANUAL")] | length')
SKIPPED=$(echo "$CHECK_RESULTS" | jq '[.items[] | select(.status == "SKIP" or .status == "NOT-APPLICABLE")] | length')

log_info "  Passing: ${PASSING}"
log_info "  Failing: ${FAILING}"
log_info "  Manual:  ${MANUAL}"
log_info "  Skipped: ${SKIPPED}"

# Load tracking data if exists
TRACKING_DATA="{}"
if [[ -f "$TRACKING_FILE" ]]; then
	TRACKING_DATA=$(cat "$TRACKING_FILE")
	log_info "Loaded tracking data from ${TRACKING_FILE}"
fi

log_info "Processing remediations by severity..."

# Helper: extract profile from check name
# e.g., "ocp4-cis-foo" -> "CIS", "rhcos4-e8-master-foo" -> "E8"
PROFILE_JQ='def extract_profile:
  if test("^ocp4-cis") then "CIS"
  elif test("^ocp4-e8") then "E8"
  elif test("^ocp4-moderate") then "Moderate"
  elif test("^ocp4-pci-dss") then "PCI-DSS"
  elif test("^rhcos4-e8") then "E8"
  elif test("^rhcos4-moderate") then "Moderate"
  else "Unknown"
  end;'

# Query checks by jq filter expression
query_checks() {
	local filter="$1"
	echo "$CHECK_RESULTS" | jq -c "${PROFILE_JQ}"'[.items[] | select('"$filter"') | {
	    name: .metadata.name,
	    check: .metadata.name,
	    status: .status,
	    description: .description,
	    severity: .severity,
	    profile: (.metadata.name | extract_profile)
	}]'
}

# Note: .severity is a top-level field, .status is the result string
HIGH_CHECKS=$(query_checks '.severity == "high" and .status == "FAIL"')
HIGH_COUNT=$(echo "$HIGH_CHECKS" | jq 'length')
log_info "  HIGH severity failing: ${HIGH_COUNT}"

MEDIUM_CHECKS=$(query_checks '.severity == "medium" and .status == "FAIL"')
MEDIUM_COUNT=$(echo "$MEDIUM_CHECKS" | jq 'length')
log_info "  MEDIUM severity failing: ${MEDIUM_COUNT}"

LOW_CHECKS=$(query_checks '.severity == "low" and .status == "FAIL"')
LOW_COUNT=$(echo "$LOW_CHECKS" | jq 'length')
log_info "  LOW severity failing: ${LOW_COUNT}"

MANUAL_CHECKS=$(query_checks '.status == "MANUAL"')
MANUAL_CHECK_COUNT=$(echo "$MANUAL_CHECKS" | jq 'length')
log_info "  MANUAL checks: ${MANUAL_CHECK_COUNT}"

log_info "Processing passing checks by severity..."

PASSING_HIGH=$(query_checks '.severity == "high" and .status == "PASS"')
PASSING_HIGH_COUNT=$(echo "$PASSING_HIGH" | jq 'length')
log_info "  HIGH severity passing: ${PASSING_HIGH_COUNT}"

PASSING_MEDIUM=$(query_checks '.severity == "medium" and .status == "PASS"')
PASSING_MEDIUM_COUNT=$(echo "$PASSING_MEDIUM" | jq 'length')
log_info "  MEDIUM severity passing: ${PASSING_MEDIUM_COUNT}"

PASSING_LOW=$(query_checks '.severity == "low" and .status == "PASS"')
PASSING_LOW_COUNT=$(echo "$PASSING_LOW" | jq 'length')
log_info "  LOW severity passing: ${PASSING_LOW_COUNT}"

# Build the output JSON
log_info "Generating JSON output..."

# Create the JSON structure (no cluster name to avoid leaking internal info)
OUTPUT_JSON=$(jq -n \
	--arg version "$OCP_VERSION" \
	--arg scan_date "$SCAN_DATE" \
	--argjson total "$TOTAL_CHECKS" \
	--argjson passing "$PASSING" \
	--argjson failing "$FAILING" \
	--argjson manual "$MANUAL" \
	--argjson skipped "$SKIPPED" \
	--argjson high "$HIGH_CHECKS" \
	--argjson medium "$MEDIUM_CHECKS" \
	--argjson low "$LOW_CHECKS" \
	--argjson manual_checks "$MANUAL_CHECKS" \
	--argjson passing_high "$PASSING_HIGH" \
	--argjson passing_medium "$PASSING_MEDIUM" \
	--argjson passing_low "$PASSING_LOW" \
	'{
        version: $version,
        scan_date: $scan_date,
        summary: {
            total_checks: $total,
            passing: $passing,
            failing: $failing,
            manual: $manual,
            skipped: $skipped
        },
        remediations: {
            high: $high,
            medium: $medium,
            low: $low
        },
        passing_checks: {
            high: $passing_high,
            medium: $passing_medium,
            low: $passing_low
        },
        manual_checks: $manual_checks
    }')

# Write output file
mkdir -p "$OUTPUT_DIR"
echo "$OUTPUT_JSON" | jq '.' >"$OUTPUT_FILE"

log_success "Successfully exported to ${OUTPUT_FILE}"

print_summary \
	"OCP Version" "${OCP_VERSION}" \
	"Scan Date" "${SCAN_DATE}" \
	"Total Checks" "${TOTAL_CHECKS}" \
	"Coverage" "$(echo "scale=1; ${PASSING} * 100 / ${TOTAL_CHECKS}" | bc)%" \
	"Failing HIGH" "${HIGH_COUNT}" \
	"Failing MEDIUM" "${MEDIUM_COUNT}" \
	"Failing LOW" "${LOW_COUNT}" \
	"MANUAL" "${MANUAL_CHECK_COUNT}"
