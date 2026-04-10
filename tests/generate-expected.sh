#!/bin/bash
# Generate expected compliance results from a live cluster
# Usage: ./tests/generate-expected.sh <OCP_VERSION>
#
# Queries all ComplianceCheckResults from the cluster and writes
# them to tests/expected-results-<version>.json. Use this to
# baseline a cluster's current state for regression testing.

set -euo pipefail

VERSION="${1:?Usage: $0 <OCP_VERSION> (e.g., 4.21, 4.22)}"
OUTPUT="tests/expected-results-${VERSION}.json"

if ! command -v jq &>/dev/null; then
	echo "ERROR: jq is required but not installed"
	exit 1
fi

echo "Generating expected results for OCP $VERSION"
echo ""

# Verify cluster connectivity
if ! oc get clusterversion &>/dev/null; then
	echo "ERROR: Cannot connect to cluster. Set KUBECONFIG or oc login first."
	exit 1
fi

CLUSTER_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null)
echo "Cluster version: $CLUSTER_VERSION"

# Get all ComplianceCheckResults
RESULTS=$(oc get compliancecheckresults -n openshift-compliance -o json 2>/dev/null)
TOTAL=$(echo "$RESULTS" | jq '.items | length')

if [[ "$TOTAL" -eq 0 ]]; then
	echo "ERROR: No ComplianceCheckResults found. Run compliance scans first."
	echo "  make install-compliance-operator"
	echo "  make apply-periodic-scan"
	echo "  (wait for scans to complete)"
	exit 1
fi

echo "Found $TOTAL ComplianceCheckResults"

# Build expected results JSON — include ALL compliance check results
echo "$RESULTS" | jq --arg version "$VERSION" --arg cluster "$CLUSTER_VERSION" '{
  version: $version,
  profiles: "all (E8, CIS, Moderate, PCI-DSS)",
  generated_from: ("Live cluster " + $cluster + " on " + (now | strftime("%Y-%m-%d"))),
  expected: (
    [.items[]
     | {(.metadata.name): .status}
    ] | add // {}
  )
}' >"$OUTPUT"

CHECKS=$(jq '.expected | length' "$OUTPUT")
FAIL=$(jq '[.expected[] | select(. == "FAIL")] | length' "$OUTPUT")
PASS=$(jq '[.expected[] | select(. == "PASS")] | length' "$OUTPUT")
MANUAL=$(jq '[.expected[] | select(. == "MANUAL")] | length' "$OUTPUT")

echo ""
echo "Written to: $OUTPUT"
echo "  Total checks: $CHECKS"
echo "  FAIL: $FAIL"
echo "  PASS: $PASS"
echo "  MANUAL: $MANUAL"
echo ""
echo "To validate against this baseline:"
echo "  make validate-compliance EXPECTED=$OUTPUT"
