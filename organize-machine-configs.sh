#!/bin/bash

# Ensure the script exits on any error
set -e

# Source and destination directories
source_dir="complianceremediations"
machineconfig_dir="/Users/bpalm/Repositories/go/src/github.com/openshift-kni/telco-reference/telco-ran/configuration/machineconfigs"
extramanifests_dir="/Users/bpalm/Repositories/go/src/github.com/openshift-kni/telco-reference/telco-ran/configuration/extra-manifests-builder"

# Precheck and create destination directories if missing
mkdir -p "$machineconfig_dir"
mkdir -p "$extramanifests_dir"

# Initialize a variable to keep track of newly created file paths
new_paths=""

# Loop through all YAML files in the source directory
for file in "$source_dir"/*.yaml; do
	# Extract the kind from the YAML
	kind=$(yq e '.kind' "$file")
	base_name=$(basename "$file")
	base_name_no_prefix=${base_name#75-}
	new_name="75-${base_name_no_prefix}"
	metadata_name="75-${base_name_no_prefix%.yaml}"

	if [[ "$kind" == "MachineConfig" ]]; then
		# Determine the topic based on the file content or name
		if grep -q "sysctl" "$file"; then
			topic="sysctl"
		elif grep -q "sshd" "$file"; then
			topic="sshd"
		else
			topic="misc"
		fi
		topic_dir="$machineconfig_dir/$topic"
		mkdir -p "$topic_dir"
		# Determine the role (master or worker) based on the filename
		if [[ "$base_name" == *"master"* ]]; then
			role="master"
		elif [[ "$base_name" == *"worker"* ]]; then
			role="worker"
		else
			role="unknown"
		fi
		# Update metadata.name and role label
		yq ".metadata.name = \"$metadata_name\" | .metadata.labels.[\"machineconfiguration.openshift.io/role\"] = \"$role\"" "$file" >"$topic_dir/$new_name"
		if ! yq e '.' "$topic_dir/$new_name" >/dev/null 2>&1; then
			echo "Warning: Invalid YAML for the new file '$topic_dir/$new_name'. Skipping."
			continue
		fi
		echo "New MachineConfig file created: $topic_dir/$new_name"
		new_paths+="$topic_dir/$new_name"$'\n'
	else
		# For non-MachineConfig, organize by kind
		kind_dir="$extramanifests_dir/$kind"
		mkdir -p "$kind_dir"
		# Update metadata.name
		yq ".metadata.name = \"$metadata_name\"" "$file" >"$kind_dir/$new_name"
		if ! yq e '.' "$kind_dir/$new_name" >/dev/null 2>&1; then
			echo "Warning: Invalid YAML for the new file '$kind_dir/$new_name'. Skipping."
			continue
		fi
		echo "New $kind file created: $kind_dir/$new_name"
		new_paths+="$kind_dir/$new_name"$'\n'
	fi
done

# Print out the list of newly created file paths in the desired format
if [[ -n "$new_paths" ]]; then
	echo "The following file paths were created:" >created_file_paths.txt
	while IFS= read -r path; do
		echo "- path: $path" >>created_file_paths.txt
	done <<<"$new_paths"
	echo "The list of created file paths has been saved to 'created_file_paths.txt'."
else
	echo "No new file paths were created."
fi

echo "All YAML files have been organized and copied to their respective directories."
