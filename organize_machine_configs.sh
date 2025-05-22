#!/bin/bash

# Ensure the script exits on any error
set -e

# Source and destination directories
source_dir="complianceremediations"
dest_dir="/Users/bpalm/Repositories/go/src/github.com/openshift-kni/cnf-features-deploy/ztp/kube-compare-reference/optional/machine-config"

# Create the destination directory if it doesn't exist
mkdir -p "$dest_dir"

# Initialize a variable to keep track of newly created file paths
new_paths=""

# Loop through all YAML files in the source directory
for file in "$source_dir"/*.yaml; do
	# Check if the file is of kind: MachineConfig
	if grep -q "kind: MachineConfig" "$file"; then
		echo "Processing $file..."

		# Determine the topic based on the file content or name
		if grep -q "sysctl" "$file"; then
			topic="sysctl"
		elif grep -q "sshd" "$file"; then
			topic="sshd"
		else
			topic="misc"
		fi

		# Create the topic folder if it doesn't exist
		topic_dir="$dest_dir/$topic"
		mkdir -p "$topic_dir"

		# Generate the new file name with the "75-" prefix
		base_name=$(basename "$file")
		# Remove any existing "75-" prefix to avoid double prefixing
		base_name_no_prefix=${base_name#75-}
		new_name="75-${base_name_no_prefix}"

		# Generate the new metadata name (remove .yaml and any existing 75- prefix)
		metadata_name="75-${base_name_no_prefix%.yaml}"

		# Determine the role (master or worker) based on the filename
		if [[ "$base_name" == *"master"* ]]; then
      role="master"
    elif [[ "$base_name" == *"worker"* ]]; then
      role="worker"
    else
      role="unknown"
    fi

		# metadata:
		# 	labels:
		# 		machineconfiguration.openshift.io/role: worker
		# 	name: 75-worker-disable-ctrlaltdel-burstaction

		# Use yq to add or update the metadata section with the name and role
		yq ".metadata.name = \"$metadata_name\" | .metadata.labels.[\"machineconfiguration.openshift.io/role\"] = \"$role\"" "$file" > "$topic_dir/$new_name"

		# Validate the new YAML file in the source directory
		if ! yq e '.' "$topic_dir/$new_name" > /dev/null 2>&1; then
			echo "Warning: Invalid YAML for the new file '$topic_dir/$new_name'. Skipping."
			continue
		fi

		# Print the new file contents
		echo "New file created: $topic_dir/$new_name"
		echo "Metadata name set to: $metadata_name"

		# Add the new file path to the list of newly created paths
		new_paths+="$topic_dir/$new_name"$'\n'
	fi
done

# Print out the list of newly created file paths in the desired format
if [[ -n "$new_paths" ]]; then
  echo "The following file paths were created:" > created_file_paths.txt
  while IFS= read -r path; do
    stripped_path="${path#*/optional}"
    echo "- path: optional$stripped_path" >> created_file_paths.txt
    # echo "- path: optional$stripped_path"
  done <<< "$new_paths"
  echo "The list of created file paths has been saved to 'created_file_paths.txt'."
else
  echo "No new file paths were created."
fi

echo "All MachineConfig files have been organized and copied to $dest_dir."


