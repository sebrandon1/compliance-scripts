#!/bin/bash
# Validate compliance scan results against expected outcomes
# Usage: ./tests/validate-results.sh tests/expected-results-4.22.json
#
# Compares actual ComplianceCheckResults from the cluster against a
# checked-in JSON file of expected results. Exits non-zero if any
# check produces an unexpected result, catching Z-stream regressions.

set -euo pipefail

EXPECTED_FILE="${1:?Usage: $0 <expected-results.json>}"

if [[ ! -f "$EXPECTED_FILE" ]]; then
	echo "ERROR: Expected results file not found: $EXPECTED_FILE"
	exit 1
fi

if ! command -v jq &>/dev/null; then
	echo "ERROR: jq is required but not installed"
	exit 1
fi

VERSION=$(jq -r '.version' "$EXPECTED_FILE")
echo "Validating compliance results for OCP $VERSION"
echo "Expected results file: $EXPECTED_FILE"
echo ""

# Get actual results from cluster
ACTUAL=$(oc get compliancecheckresults -n openshift-compliance -o json 2>/dev/null)
ACTUAL_COUNT=$(echo "$ACTUAL" | jq '.items | length')
echo "Found $ACTUAL_COUNT ComplianceCheckResults in cluster"
echo ""

PASS=0
FAIL=0
MISS=0
TOTAL=0

for check in $(jq -r '.expected | keys[]' "$EXPECTED_FILE"); do
	EXPECTED_STATUS=$(jq -r ".expected[\"$check\"]" "$EXPECTED_FILE")
	ACTUAL_STATUS=$(echo "$ACTUAL" | jq -r ".items[] | select(.metadata.name==\"$check\") | .status" 2>/dev/null)
	TOTAL=$((TOTAL + 1))

	if [[ "$ACTUAL_STATUS" == "$EXPECTED_STATUS" ]]; then
		PASS=$((PASS + 1))
	elif [[ -z "$ACTUAL_STATUS" ]]; then
		echo "MISS: $check expected=$EXPECTED_STATUS actual=not_found"
		MISS=$((MISS + 1))
	else
		echo "REGRESSION: $check expected=$EXPECTED_STATUS actual=$ACTUAL_STATUS"
		FAIL=$((FAIL + 1))
	fi
done

echo ""
echo "========================================"
echo "  Validation Summary (OCP $VERSION)"
echo "========================================"
echo "  Total checks:  $TOTAL"
echo "  Matching:      $PASS"
echo "  Regressions:   $FAIL"
echo "  Missing:       $MISS"
echo "========================================"

if [[ $FAIL -gt 0 ]]; then
	echo ""
	echo "FAILED: $FAIL check(s) produced unexpected results."
	echo "This may indicate a Z-stream regression in RHCOS or SCAP content."
	echo "Review the REGRESSION lines above and update the expected results"
	echo "file if the change is intentional."
	exit 1
elif [[ $MISS -gt 0 ]]; then
	echo ""
	echo "WARNING: $MISS check(s) were expected but not found in scan results."
	echo "These may be notapplicable on this cluster configuration."
	exit 0
else
	echo ""
	echo "All checks match expected results."
	exit 0
fi
