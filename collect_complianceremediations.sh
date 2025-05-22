#!/bin/bash

# Ensure the script exits on any error
set -e

# Check if the 'oc' command-line client is installed
if ! command -v oc &> /dev/null; then
  echo "Error: 'oc' command-line client is not installed. Please install it and try again."
  exit 1
fi

# Check if the 'yq' command-line client is installed
if ! command -v yq &> /dev/null; then
  echo "Error: 'yq' command-line client is not installed. Please install it and try again."
  exit 1
fi

# Directory to store the YAML files
destination_dir="complianceremediations"

# Remove the destination directory if it exists to start fresh
echo "[INFO] Removing existing $destination_dir directory (if any) to start fresh."
rm -rf "$destination_dir"

# Create the directory if it doesn't exist
mkdir -p "$destination_dir"

# Accept namespace as an argument, default to 'openshift-compliance'
NAMESPACE="${1:-openshift-compliance}"
echo "[INFO] Using namespace: $NAMESPACE"

# Fetch all complianceremediation objects in YAML format
complianceremediations=$(oc get complianceremediation -n "$NAMESPACE" -o yaml)

# Extract the names of the complianceremediation objects
names=$(echo "$complianceremediations" | yq e '.items[].metadata.name' -)

# Counters for logging
count_total=0
count_valid=0
count_invalid=0
kinds=()

# Loop through each complianceremediation object
for name in $names; do
  # Extract the spec.object YAML structure for the current object
  spec_object=$(echo "$complianceremediations" | yq e ".items[] | select(.metadata.name == \"$name\") | .spec.current.object" -)

  # Validate the YAML structure of the spec.object
  if ! echo "$spec_object" | yq e '.' - > /dev/null 2>&1; then
    echo "Warning: Invalid YAML for complianceremediation object '$name'. Skipping."
    count_invalid=$((count_invalid+1))
    count_total=$((count_total+1))
    continue
  fi

  # Save the spec.object YAML to a file named after the complianceremediation object
  echo "$spec_object" > "$destination_dir/$name.yaml"
  count_valid=$((count_valid+1))
  count_total=$((count_total+1))

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
echo "Kinds found in collected objects:"
echo "$unique_kinds"

echo "All complianceremediation objects have been saved to the $destination_dir directory."