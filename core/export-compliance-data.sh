#!/bin/bash
# export-compliance-data.sh
# Exports Compliance Operator check results to JSON for GitHub Pages dashboard
#
# Usage: ./export-compliance-data.sh <ocp-version>
# Example: ./export-compliance-data.sh 4.17
#
# Requires: oc, jq
# Environment: KUBECONFIG must be set to target cluster

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${COMPLIANCE_NAMESPACE:-openshift-compliance}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${REPO_ROOT}/docs/_data"
TRACKING_FILE="${OUTPUT_DIR}/tracking.json"

# Validate arguments
if [[ $# -lt 1 ]]; then
    echo -e "${RED}Error: OCP version required${NC}"
    echo "Usage: $0 <ocp-version>"
    echo "Example: $0 4.17"
    exit 1
fi

OCP_VERSION="$1"
# Replace dots with underscores for Jekyll compatibility
VERSION_SLUG="${OCP_VERSION//./_}"
OUTPUT_FILE="${OUTPUT_DIR}/ocp-${VERSION_SLUG}.json"

echo -e "${BLUE}=== Compliance Data Export ===${NC}"
echo -e "OCP Version: ${GREEN}${OCP_VERSION}${NC}"
echo -e "Namespace: ${NAMESPACE}"
echo -e "Output: ${OUTPUT_FILE}"

# Check prerequisites
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: 'oc' command not found${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: 'jq' command not found${NC}"
    exit 1
fi

# Verify cluster connection
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged into OpenShift cluster${NC}"
    echo "Please set KUBECONFIG or run 'oc login'"
    exit 1
fi

# Verify cluster connection (but don't expose cluster name in output)
echo -e "Cluster: ${GREEN}connected${NC}"

# Get current timestamp
SCAN_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo -e "\n${BLUE}Collecting ComplianceCheckResults...${NC}"

# Collect all check results
CHECK_RESULTS=$(oc get compliancecheckresults -n "${NAMESPACE}" -o json 2>/dev/null)

if [[ -z "$CHECK_RESULTS" ]] || [[ "$(echo "$CHECK_RESULTS" | jq '.items | length')" -eq 0 ]]; then
    echo -e "${RED}Error: No ComplianceCheckResults found in namespace ${NAMESPACE}${NC}"
    exit 1
fi

TOTAL_CHECKS=$(echo "$CHECK_RESULTS" | jq '.items | length')
echo -e "Found ${GREEN}${TOTAL_CHECKS}${NC} compliance checks"

# Count by status
# Note: .status is a string field (e.g., "PASS", "FAIL", "MANUAL"), not an object
PASSING=$(echo "$CHECK_RESULTS" | jq '[.items[] | select(.status == "PASS")] | length')
FAILING=$(echo "$CHECK_RESULTS" | jq '[.items[] | select(.status == "FAIL")] | length')
MANUAL=$(echo "$CHECK_RESULTS" | jq '[.items[] | select(.status == "MANUAL")] | length')
SKIPPED=$(echo "$CHECK_RESULTS" | jq '[.items[] | select(.status == "SKIP" or .status == "NOT-APPLICABLE")] | length')

echo -e "  Passing: ${GREEN}${PASSING}${NC}"
echo -e "  Failing: ${RED}${FAILING}${NC}"
echo -e "  Manual:  ${YELLOW}${MANUAL}${NC}"
echo -e "  Skipped: ${SKIPPED}"

# Load tracking data if exists
TRACKING_DATA="{}"
if [[ -f "$TRACKING_FILE" ]]; then
    TRACKING_DATA=$(cat "$TRACKING_FILE")
    echo -e "\n${BLUE}Loaded tracking data from ${TRACKING_FILE}${NC}"
fi

# Function to get tracking info for a remediation
get_tracking_info() {
    local check_name="$1"
    # Strip prefix like rhcos4-e8-worker- or ocp4-cis-
    local base_name=$(echo "$check_name" | sed -E 's/^(rhcos4-e8|ocp4-cis|ocp4-e8)-(master|worker)-//')

    local jira=$(echo "$TRACKING_DATA" | jq -r ".remediations[\"${base_name}\"].jira // empty")
    local pr=$(echo "$TRACKING_DATA" | jq -r ".remediations[\"${base_name}\"].pr // empty")
    local status=$(echo "$TRACKING_DATA" | jq -r ".remediations[\"${base_name}\"].status // empty")

    echo "{\"jira\": \"${jira}\", \"pr\": \"${pr}\", \"tracking_status\": \"${status}\"}"
}

echo -e "\n${BLUE}Processing remediations by severity...${NC}"

# Process HIGH severity failing checks
# Note: .severity is a top-level field, .status is the result string
HIGH_CHECKS=$(echo "$CHECK_RESULTS" | jq -c '[.items[] | select(.severity == "high" and .status == "FAIL") | {
    name: .metadata.name,
    check: .metadata.name,
    status: .status,
    description: .description,
    severity: .severity
}]')

HIGH_COUNT=$(echo "$HIGH_CHECKS" | jq 'length')
echo -e "  HIGH severity failing: ${RED}${HIGH_COUNT}${NC}"

# Process MEDIUM severity failing checks
MEDIUM_CHECKS=$(echo "$CHECK_RESULTS" | jq -c '[.items[] | select(.severity == "medium" and .status == "FAIL") | {
    name: .metadata.name,
    check: .metadata.name,
    status: .status,
    description: .description,
    severity: .severity
}]')

MEDIUM_COUNT=$(echo "$MEDIUM_CHECKS" | jq 'length')
echo -e "  MEDIUM severity failing: ${YELLOW}${MEDIUM_COUNT}${NC}"

# Process LOW severity failing checks
LOW_CHECKS=$(echo "$CHECK_RESULTS" | jq -c '[.items[] | select(.severity == "low" and .status == "FAIL") | {
    name: .metadata.name,
    check: .metadata.name,
    status: .status,
    description: .description,
    severity: .severity
}]')

LOW_COUNT=$(echo "$LOW_CHECKS" | jq 'length')
echo -e "  LOW severity failing: ${BLUE}${LOW_COUNT}${NC}"

# Process MANUAL checks
MANUAL_CHECKS=$(echo "$CHECK_RESULTS" | jq -c '[.items[] | select(.status == "MANUAL") | {
    name: .metadata.name,
    check: .metadata.name,
    status: .status,
    description: .description,
    severity: .severity
}]')

MANUAL_CHECK_COUNT=$(echo "$MANUAL_CHECKS" | jq 'length')
echo -e "  MANUAL checks: ${YELLOW}${MANUAL_CHECK_COUNT}${NC}"

# Build the output JSON
echo -e "\n${BLUE}Generating JSON output...${NC}"

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
        manual_checks: $manual_checks
    }')

# Write output file
mkdir -p "$OUTPUT_DIR"
echo "$OUTPUT_JSON" | jq '.' > "$OUTPUT_FILE"

echo -e "${GREEN}Successfully exported to ${OUTPUT_FILE}${NC}"

# Print summary
echo -e "\n${BLUE}=== Summary ===${NC}"
echo -e "OCP Version: ${OCP_VERSION}"
echo -e "Scan Date: ${SCAN_DATE}"
echo -e "Total Checks: ${TOTAL_CHECKS}"
echo -e "Coverage: $(echo "scale=1; ${PASSING} * 100 / ${TOTAL_CHECKS}" | bc)%"
echo -e "Failing by severity:"
echo -e "  HIGH:   ${HIGH_COUNT}"
echo -e "  MEDIUM: ${MEDIUM_COUNT}"
echo -e "  LOW:    ${LOW_COUNT}"
echo -e "  MANUAL: ${MANUAL_CHECK_COUNT}"
