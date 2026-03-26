#!/bin/bash
# Validate compliance scan results against expected outcomes
# Usage: ./tests/validate-results.sh tests/expected-results-4.22.json
#
# Compares actual ComplianceCheckResults from the cluster against a
# checked-in JSON file of expected results. Exits non-zero if any
# check produces an unexpected result, catching Z-stream regressions.
# Also detects new checks not in the baseline (SCAP content updates).

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
PROFILE_FILTER=$(jq -r '.profile // ""' "$EXPECTED_FILE")
echo "Validating compliance results for OCP $VERSION"
echo "Expected results file: $EXPECTED_FILE"
echo ""

# Get actual results from cluster
ACTUAL=$(oc get compliancecheckresults -n openshift-compliance -o json 2>/dev/null)
ACTUAL_COUNT=$(echo "$ACTUAL" | jq '.items | length')
echo "Found $ACTUAL_COUNT ComplianceCheckResults in cluster"
echo ""

MATCH=0
REGRESSION=0
MISS=0
NEW=0
TOTAL=0

# Phase 1: Validate expected checks against actual results
echo "--- Checking expected results ---"
for check in $(jq -r '.expected | keys[]' "$EXPECTED_FILE"); do
	EXPECTED_STATUS=$(jq -r ".expected[\"$check\"]" "$EXPECTED_FILE")
	ACTUAL_STATUS=$(echo "$ACTUAL" | jq -r ".items[] | select(.metadata.name==\"$check\") | .status" 2>/dev/null)
	TOTAL=$((TOTAL + 1))

	if [[ "$ACTUAL_STATUS" == "$EXPECTED_STATUS" ]]; then
		MATCH=$((MATCH + 1))
	elif [[ -z "$ACTUAL_STATUS" ]]; then
		echo "MISS: $check expected=$EXPECTED_STATUS actual=not_found"
		MISS=$((MISS + 1))
	else
		echo "REGRESSION: $check expected=$EXPECTED_STATUS actual=$ACTUAL_STATUS"
		REGRESSION=$((REGRESSION + 1))
	fi
done

# Phase 2: Detect new checks not in baseline
echo ""
echo "--- Checking for new checks ---"
EXPECTED_KEYS=$(jq -r '.expected | keys[]' "$EXPECTED_FILE" | sort)
ACTUAL_E8=$(echo "$ACTUAL" | jq -r '.items[] | select(.metadata.name | test("^(rhcos4-e8|ocp4-e8)")) | .metadata.name' | sort)

NEW_CHECKS=$(comm -23 <(echo "$ACTUAL_E8") <(echo "$EXPECTED_KEYS"))

if [[ -n "$NEW_CHECKS" ]]; then
	while IFS= read -r check; do
		STATUS=$(echo "$ACTUAL" | jq -r ".items[] | select(.metadata.name==\"$check\") | .status" 2>/dev/null)
		echo "NEW: $check status=$STATUS (not in baseline)"
		NEW=$((NEW + 1))
	done <<<"$NEW_CHECKS"
else
	echo "No new checks detected."
fi

# Phase 3: Detect removed checks (in baseline but E8 checks gone from cluster entirely)
REMOVED_CHECKS=$(comm -23 <(echo "$EXPECTED_KEYS") <(echo "$ACTUAL_E8"))
REMOVED=0
if [[ -n "$REMOVED_CHECKS" ]]; then
	# Only count truly removed checks (not already counted as MISS)
	while IFS= read -r check; do
		if echo "$check" | grep -qE "^(rhcos4-e8|ocp4-e8)"; then
			REMOVED=$((REMOVED + 1))
		fi
	done <<<"$REMOVED_CHECKS"
fi

echo ""
echo "========================================"
echo "  Validation Summary (OCP $VERSION)"
echo "========================================"
echo "  Expected checks: $TOTAL"
echo "  Matching:        $MATCH"
echo "  Regressions:     $REGRESSION"
echo "  Missing:         $MISS"
echo "  New checks:      $NEW"
echo "  Removed checks:  $REMOVED"
echo "========================================"

EXIT_CODE=0

if [[ $REGRESSION -gt 0 ]]; then
	echo ""
	echo "FAILED: $REGRESSION check(s) produced unexpected results."
	echo "This may indicate a Z-stream regression in RHCOS or SCAP content."
	echo "Review the REGRESSION lines above and update the expected results"
	echo "file if the change is intentional."
	EXIT_CODE=1
fi

if [[ $NEW -gt 0 ]]; then
	echo ""
	echo "INFO: $NEW new check(s) found that are not in the baseline."
	echo "These may be from a SCAP content update. Consider adding them"
	echo "to the expected results file and assigning to a remediation group."
fi

if [[ $MISS -gt 0 ]]; then
	echo ""
	echo "WARNING: $MISS check(s) were expected but not found in scan results."
	echo "These may be notapplicable on this cluster configuration."
fi

if [[ $REMOVED -gt 0 ]]; then
	echo ""
	echo "WARNING: $REMOVED check(s) from the baseline are no longer produced."
	echo "These may have been removed from the SCAP content."
fi

if [[ $EXIT_CODE -eq 0 && $NEW -eq 0 && $MISS -eq 0 ]]; then
	echo ""
	echo "All checks match expected results."
fi

exit $EXIT_CODE
