#!/bin/bash
# generate-compliance-markdown.sh - Generate a Markdown compliance report
#
# Queries all ComplianceCheckResult objects from the connected OpenShift cluster
# and produces a Markdown table (ComplianceCheckResults.md) mapping each check
# to its remediation file, severity, and pass/fail/manual result.
#
# Prerequisites:
#   - Compliance scans must have completed (ComplianceCheckResults exist)
#   - Remediations should be collected first (collect-complianceremediations.sh)
#     so that file links resolve correctly
#
# Output: ComplianceCheckResults.md (in the current directory)
#
# Usage: ./core/generate-compliance-markdown.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_cmd oc

output_file="ComplianceCheckResults.md"

compliance_results=$(oc get compliancecheckresult -A)

fail_rows=""
pass_rows=""
manual_rows=""

while IFS= read -r line; do
	[[ "$line" == *"NAMESPACE"* ]] && continue
	namespace=$(echo "$line" | awk '{print $1}')
	name=$(echo "$line" | awk '{print $2}')
	result=$(echo "$line" | awk '{print $3}')
	severity=$(echo "$line" | awk '{print $4}')

	file="complianceremediations/$name.yaml"
	if [[ -f "$file" ]]; then
		file_link="[$name.yaml]($file)"
	else
		file_link="N/A"
	fi

	row="| $namespace | $name | $result | $severity | $file_link |"
	case "$result" in
	FAIL) fail_rows+="$row"$'\n' ;;
	PASS) pass_rows+="$row"$'\n' ;;
	MANUAL) manual_rows+="$row"$'\n' ;;
	esac
done <<<"$compliance_results"

{
	echo "# Compliance Check Results"
	echo ""
	echo "## FAIL Results"
	echo "| Namespace | Name | Result | Severity | File |"
	echo "|-----------|------|--------|----------|------|"
	printf "%s" "$fail_rows"
	echo ""
	echo "## PASS Results"
	echo "| Namespace | Name | Result | Severity | File |"
	echo "|-----------|------|--------|----------|------|"
	printf "%s" "$pass_rows"
	echo ""
	echo "## MANUAL Results"
	echo "| Namespace | Name | Result | Severity | File |"
	echo "|-----------|------|--------|----------|------|"
	printf "%s" "$manual_rows"
	echo ""
} >"$output_file"

echo "Markdown file '$output_file' has been created."
