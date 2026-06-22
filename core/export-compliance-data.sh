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

# Capture content image from ProfileBundles
log_info "Capturing content image..."
CONTENT_IMAGE=$(oc get profilebundle -n "${NAMESPACE}" -o jsonpath='{.items[0].spec.contentImage}' 2>/dev/null || echo "unknown")
CONTENT_IMAGE_DIGEST=$(oc get profilebundle -n "${NAMESPACE}" -o jsonpath='{.items[0].status.dataStreamStatus.image}' 2>/dev/null || echo "")
if [[ -z "$CONTENT_IMAGE_DIGEST" ]]; then
	CONTENT_IMAGE_DIGEST=$(skopeo inspect "docker://${CONTENT_IMAGE}" 2>/dev/null | jq -r '.Digest // empty' || echo "")
fi
log_info "Content image: ${CONTENT_IMAGE}"
if [[ -n "$CONTENT_IMAGE_DIGEST" ]]; then
	log_info "Content digest: ${CONTENT_IMAGE_DIGEST}"
fi

log_info "Collecting ComplianceCheckResults..."

# Collect all check results
CHECK_RESULTS=$(oc get compliancecheckresults -n "${NAMESPACE}" -o json 2>/dev/null)

if [[ -z "$CHECK_RESULTS" ]] || [[ "$(echo "$CHECK_RESULTS" | jq '.items | length')" -eq 0 ]]; then
	log_error "No ComplianceCheckResults found in namespace ${NAMESPACE}"
	exit 1
fi

SUMMARY=$(echo "$CHECK_RESULTS" | jq '{
	total: (.items | length),
	passing: [.items[] | select(.status == "PASS")] | length,
	failing: [.items[] | select(.status == "FAIL")] | length,
	manual: [.items[] | select(.status == "MANUAL")] | length,
	skipped: [.items[] | select(.status == "SKIP" or .status == "NOT-APPLICABLE")] | length,
	rhcos_failing: [.items[] | select(.status == "FAIL" and (.metadata.name | test("^rhcos4-")))] | length,
	ocp_failing: [.items[] | select(.status == "FAIL" and (.metadata.name | test("^ocp4-")))] | length
}')

TOTAL_CHECKS=$(echo "$SUMMARY" | jq '.total')
PASSING=$(echo "$SUMMARY" | jq '.passing')
FAILING=$(echo "$SUMMARY" | jq '.failing')
MANUAL=$(echo "$SUMMARY" | jq '.manual')
SKIPPED=$(echo "$SUMMARY" | jq '.skipped')
RHCOS_FAILING=$(echo "$SUMMARY" | jq '.rhcos_failing')
OCP_FAILING=$(echo "$SUMMARY" | jq '.ocp_failing')

log_info "Found ${TOTAL_CHECKS} compliance checks"
log_info "  Passing: ${PASSING}"
log_info "  Failing: ${FAILING}"
log_info "  Manual:  ${MANUAL}"
log_info "  Skipped: ${SKIPPED}"
log_info "  RHCOS failing: ${RHCOS_FAILING}"
log_info "  OCP failing:   ${OCP_FAILING}"

# Load tracking data if exists
TRACKING_DATA="{}"
if [[ -f "$TRACKING_FILE" ]]; then
	TRACKING_DATA=$(cat "$TRACKING_FILE")
	log_info "Loaded tracking data from ${TRACKING_FILE}"
fi

PROFILE_JQ='def extract_profile:
  if test("^ocp4-cis") then "CIS"
  elif test("^ocp4-e8") then "E8"
  elif test("^ocp4-moderate") then "Moderate"
  elif test("^ocp4-pci-dss") then "PCI-DSS"
  elif test("^rhcos4-e8") then "E8"
  elif test("^rhcos4-moderate") then "Moderate"
  else "Unknown"
  end;
def extract_platform:
  if test("^rhcos4-") then "rhcos"
  elif test("^ocp4-") then "ocp"
  else "unknown"
  end;
def to_check:
  {name: .metadata.name, check: .metadata.name, status, description, severity,
   profile: (.metadata.name | extract_profile),
   platform: (.metadata.name | extract_platform)};'

log_info "Processing checks by severity..."
CLASSIFIED=$(echo "$CHECK_RESULTS" | jq -c "${PROFILE_JQ}"'{
	fail_high:    [.items[] | select(.severity == "high"   and .status == "FAIL")   | to_check],
	fail_medium:  [.items[] | select(.severity == "medium" and .status == "FAIL")   | to_check],
	fail_low:     [.items[] | select(.severity == "low"    and .status == "FAIL")   | to_check],
	manual:       [.items[] | select(.status == "MANUAL")                           | to_check],
	pass_high:    [.items[] | select(.severity == "high"   and .status == "PASS")   | to_check],
	pass_medium:  [.items[] | select(.severity == "medium" and .status == "PASS")   | to_check],
	pass_low:     [.items[] | select(.severity == "low"    and .status == "PASS")   | to_check]
}')

HIGH_CHECKS=$(echo "$CLASSIFIED" | jq -c '.fail_high')
MEDIUM_CHECKS=$(echo "$CLASSIFIED" | jq -c '.fail_medium')
LOW_CHECKS=$(echo "$CLASSIFIED" | jq -c '.fail_low')
MANUAL_CHECKS=$(echo "$CLASSIFIED" | jq -c '.manual')
PASSING_HIGH=$(echo "$CLASSIFIED" | jq -c '.pass_high')
PASSING_MEDIUM=$(echo "$CLASSIFIED" | jq -c '.pass_medium')
PASSING_LOW=$(echo "$CLASSIFIED" | jq -c '.pass_low')

HIGH_COUNT=$(echo "$CLASSIFIED" | jq '.fail_high | length')
MEDIUM_COUNT=$(echo "$CLASSIFIED" | jq '.fail_medium | length')
LOW_COUNT=$(echo "$CLASSIFIED" | jq '.fail_low | length')
MANUAL_CHECK_COUNT=$(echo "$CLASSIFIED" | jq '.manual | length')
PASSING_HIGH_COUNT=$(echo "$CLASSIFIED" | jq '.pass_high | length')
PASSING_MEDIUM_COUNT=$(echo "$CLASSIFIED" | jq '.pass_medium | length')
PASSING_LOW_COUNT=$(echo "$CLASSIFIED" | jq '.pass_low | length')

log_info "  HIGH severity failing: ${HIGH_COUNT}"
log_info "  MEDIUM severity failing: ${MEDIUM_COUNT}"
log_info "  LOW severity failing: ${LOW_COUNT}"
log_info "  MANUAL checks: ${MANUAL_CHECK_COUNT}"
log_info "  HIGH severity passing: ${PASSING_HIGH_COUNT}"
log_info "  MEDIUM severity passing: ${PASSING_MEDIUM_COUNT}"
log_info "  LOW severity passing: ${PASSING_LOW_COUNT}"

# Build the output JSON
log_info "Generating JSON output..."

OUTPUT_JSON=$(jq -n \
	--arg version "$OCP_VERSION" \
	--arg scan_date "$SCAN_DATE" \
	--arg content_image "$CONTENT_IMAGE" \
	--arg content_image_digest "$CONTENT_IMAGE_DIGEST" \
	--argjson total "$TOTAL_CHECKS" \
	--argjson passing "$PASSING" \
	--argjson failing "$FAILING" \
	--argjson manual "$MANUAL" \
	--argjson skipped "$SKIPPED" \
	--argjson rhcos_failing "$RHCOS_FAILING" \
	--argjson ocp_failing "$OCP_FAILING" \
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
        content_image: $content_image,
        content_image_digest: (if $content_image_digest == "" then null else $content_image_digest end),
        summary: {
            total_checks: $total,
            passing: $passing,
            failing: $failing,
            manual: $manual,
            skipped: $skipped,
            rhcos_failing: $rhcos_failing,
            ocp_failing: $ocp_failing
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
	"Content Image" "${CONTENT_IMAGE}" \
	"Total Checks" "${TOTAL_CHECKS}" \
	"Coverage" "$(echo "scale=1; ${PASSING} * 100 / ${TOTAL_CHECKS}" | bc)%" \
	"Failing HIGH" "${HIGH_COUNT}" \
	"Failing MEDIUM" "${MEDIUM_COUNT}" \
	"Failing LOW" "${LOW_COUNT}" \
	"MANUAL" "${MANUAL_CHECK_COUNT}"
