#!/bin/bash

# Ensure the script exits on any error
set -e

# Check if the 'oc' command-line client is installed
if ! command -v oc &>/dev/null; then
	echo "Error: 'oc' command-line client is not installed. Please install it and try again."
	exit 1
fi

# Output Markdown file
output_file="ComplianceCheckResults.md"

# Fetch all ComplianceCheckResult objects
compliance_results=$(oc get compliancecheckresult -A)

# Start writing the Markdown file
echo "# Compliance Check Results" >"$output_file"
echo "" >>"$output_file"

echo "## FAIL Results" >>"$output_file"
echo "| Namespace | Name | Result | Severity | File |" >>"$output_file"
echo "|-----------|------|--------|----------|------|" >>"$output_file"

# Parse the ComplianceCheckResult output and map to files
while IFS= read -r line; do
	# Skip the header line
	if [[ "$line" == *"NAMESPACE"* ]]; then
		continue
	fi

	# Extract fields from the line
	namespace=$(echo "$line" | awk '{print $1}')
	name=$(echo "$line" | awk '{print $2}')
	result=$(echo "$line" | awk '{print $3}')
	severity=$(echo "$line" | awk '{print $4}')

	# Check if a corresponding file exists
	file="complianceremediations/$name.yaml"
	if [[ -f "$file" ]]; then
		file_link="[$name.yaml]($file)"
	else
		file_link="N/A"
	fi

	# Append rows to the appropriate section based on the result
	if [[ "$result" == "FAIL" ]]; then
		echo "| $namespace | $name | $result | $severity | $file_link |" >>"$output_file"
	fi
done <<<"$compliance_results"

echo "" >>"$output_file"
echo "## PASS Results" >>"$output_file"
echo "| Namespace | Name | Result | Severity | File |" >>"$output_file"
echo "|-----------|------|--------|----------|------|" >>"$output_file"

while IFS= read -r line; do
	# Skip the header line
	if [[ "$line" == *"NAMESPACE"* ]]; then
		continue
	fi

	# Extract fields from the line
	namespace=$(echo "$line" | awk '{print $1}')
	name=$(echo "$line" | awk '{print $2}')
	result=$(echo "$line" | awk '{print $3}')
	severity=$(echo "$line" | awk '{print $4}')

	# Check if a corresponding file exists
	file="complianceremediations/$name.yaml"
	if [[ -f "$file" ]]; then
		file_link="[$name.yaml]($file)"
	else
		file_link="N/A"
	fi

	if [[ "$result" == "PASS" ]]; then
		echo "| $namespace | $name | $result | $severity | $file_link |" >>"$output_file"
	fi
done <<<"$compliance_results"

echo "" >>"$output_file"
echo "## MANUAL Results" >>"$output_file"
echo "| Namespace | Name | Result | Severity | File |" >>"$output_file"
echo "|-----------|------|--------|----------|------|" >>"$output_file"

while IFS= read -r line; do
	# Skip the header line
	if [[ "$line" == *"NAMESPACE"* ]]; then
		continue
	fi

	# Extract fields from the line
	namespace=$(echo "$line" | awk '{print $1}')
	name=$(echo "$line" | awk '{print $2}')
	result=$(echo "$line" | awk '{print $3}')
	severity=$(echo "$line" | awk '{print $4}')

	# Check if a corresponding file exists
	file="complianceremediations/$name.yaml"
	if [[ -f "$file" ]]; then
		file_link="[$name.yaml]($file)"
	else
		file_link="N/A"
	fi

	if [[ "$result" == "MANUAL" ]]; then
		echo "| $namespace | $name | $result | $severity | $file_link |" >>"$output_file"
	fi
done <<<"$compliance_results"

echo "" >>"$output_file"
echo "Markdown file '$output_file' has been created."
