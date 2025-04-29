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

# Create the directory if it doesn't exist
mkdir -p "$destination_dir"

# Fetch all complianceremediation objects in YAML format
complianceremediations=$(oc get complianceremediation -o yaml)

# Extract the names of the complianceremediation objects
names=$(echo "$complianceremediations" | yq e '.items[].metadata.name' -)

# Loop through each complianceremediation object
for name in $names; do
  # Extract the spec.object YAML structure for the current object
  spec_object=$(echo "$complianceremediations" | yq e ".items[] | select(.metadata.name == \"$name\") | .spec.current.object" -)

  # Validate the YAML structure of the spec.object
  if ! echo "$spec_object" | yq e '.' - > /dev/null 2>&1; then
    echo "Warning: Invalid YAML for complianceremediation object '$name'. Skipping."
    continue
  fi

  # Save the spec.object YAML to a file named after the complianceremediation object
  echo "$spec_object" > "$destination_dir/$name.yaml"

done

echo "All complianceremediation objects have been saved to the $destination_dir directory."