#!/bin/bash

# Ensure the script exits on any error
set -e

# Check if the 'oc' command-line client is installed
if ! command -v oc &>/dev/null; then
	echo "Error: 'oc' command-line client is not installed. Please install it and try again."
	exit 1
fi

# Check if the 'yq' command-line client is installed
if ! command -v yq &>/dev/null; then
	echo "Error: 'yq' command-line client is not installed. Please install it and try again."
	exit 1
fi

# Pre-check: Ensure the cluster is available before proceeding
if ! oc whoami &>/dev/null; then
	echo "Error: Unable to connect to the cluster. Please ensure you are logged in with 'oc login' and the cluster is reachable."
	exit 1
fi

# Directory to store the YAML files
destination_dir="complianceremediations"

# (Default behavior) Preserve existing destination directory across runs

# Parse arguments
print_usage() {
	echo "Usage: $0 [-n|--namespace NAMESPACE] [-s|--severity SEVERITY[,SEVERITY...]] [-f|--fresh]"
	echo "\nOptions:"
	echo "  -n, --namespace   Namespace for complianceremediation objects (default: openshift-compliance)"
	echo "  -s, --severity    Comma-separated severities to include: high,medium,low (case-insensitive)"
	echo "  -f, --fresh       Remove existing output directory before collecting"
	echo "  -h, --help        Show this help message"
}

NAMESPACE_DEFAULT="openshift-compliance"
NAMESPACE="$NAMESPACE_DEFAULT"
SEVERITY_FILTER=""
CLEAN_OUTPUT=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		-n|--namespace)
			NAMESPACE="$2"
			shift 2
			;;
		-s|--severity)
			SEVERITY_FILTER="$2"
			shift 2
			;;
		-f|--fresh)
			CLEAN_OUTPUT=1
			shift
			;;
		-h|--help)
			print_usage
			exit 0
			;;
		--)
			shift
			break
			;;
		-*)
			echo "Error: Unknown option: $1"
			print_usage
			exit 1
			;;
		*)
			# Backward compatibility: treat first non-flag arg as namespace if not set explicitly
			if [[ "$NAMESPACE" == "$NAMESPACE_DEFAULT" ]]; then
				NAMESPACE="$1"
				shift
				continue
			fi
			echo "Error: Unexpected argument: $1"
			print_usage
			exit 1
			;;
	esac
done

echo "[INFO] Using namespace: $NAMESPACE"
# Prepare output directory
if [[ $CLEAN_OUTPUT -eq 1 ]]; then
    echo "[INFO] Removing existing $destination_dir directory to start fresh."
    rm -rf "$destination_dir"
fi
mkdir -p "$destination_dir"

if [[ -n "$SEVERITY_FILTER" ]]; then
	# Normalize and validate severity filter (comma-separated list)
	SEVERITY_FILTER=$(echo "$SEVERITY_FILTER" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
	IFS=',' read -r -a severity_list <<<"$SEVERITY_FILTER"
	for s in "${severity_list[@]}"; do
		if [[ "$s" != "high" && "$s" != "medium" && "$s" != "low" ]]; then
			echo "Error: Invalid severity '$s'. Allowed values: high, medium, low"
			exit 1
		fi
	done
	echo "[INFO] Severity filter enabled: $SEVERITY_FILTER"
	# Create subdirectories for each requested severity under the destination directory
	for s in "${severity_list[@]}"; do
		mkdir -p "$destination_dir/$s"
	done
fi

# Fetch all complianceremediation objects in YAML format
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
	# Apply severity filter if requested
	check_severity=$(echo "$severity_lines" | awk -v n="$name" '$1==n{print $2; exit}')
	if [[ -n "$SEVERITY_FILTER" ]]; then
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
			count_total=$((count_total + 1))
			continue
		fi
	fi
	# Extract the spec.object YAML structure for the current object
	spec_object=$(echo "$complianceremediations" | yq e ".items[] | select(.metadata.name == \"$name\") | .spec.current.object" -)

	# Validate the YAML structure of the spec.object
	if ! echo "$spec_object" | yq e '.' - >/dev/null 2>&1; then
		echo "Warning: Invalid YAML for complianceremediation object '$name'. Skipping."
		count_invalid=$((count_invalid + 1))
		count_total=$((count_total + 1))
		continue
	fi

	# Determine output directory (severity subfolder if filter specified)
	output_dir="$destination_dir"
	if [[ -n "$SEVERITY_FILTER" && -n "$check_severity" ]]; then
		output_dir="$destination_dir/$check_severity"
	fi
	mkdir -p "$output_dir"
	# Save the spec.object YAML to a file named after the complianceremediation object
	echo "$spec_object" >"$output_dir/$name.yaml"
	count_valid=$((count_valid + 1))
	count_total=$((count_total + 1))

	# Extract kind if possible
	kind=$(echo "$spec_object" | yq e '.kind' - 2>/dev/null)
	if [[ -n "$kind" && "$kind" != "null" ]]; then
		kinds+=("$kind")
	fi

done

# Print summary
unique_kinds=$(printf "%s\n" "${kinds[@]}" | sort | uniq -c | sort -nr)
echo -e "\n[SUMMARY]"
echo "Total complianceremediation objects processed: $count_total"
echo "Valid YAMLs collected: $count_valid"
echo "Invalid YAMLs skipped: $count_invalid"
if [[ -n "$SEVERITY_FILTER" ]]; then
echo "Skipped due to severity filter ($SEVERITY_FILTER): $count_skipped_severity"
fi
echo "Kinds found in collected objects:"
echo "$unique_kinds"

echo "All complianceremediation objects have been saved to the $destination_dir directory."
