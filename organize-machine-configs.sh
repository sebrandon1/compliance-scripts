#!/bin/bash

# Ensure the script exits on any error
set -e

# Default directories
source_dir="complianceremediations"
machineconfig_dir="/Users/bpalm/Repositories/go/src/github.com/openshift-kni/telco-reference/telco-ran/configuration/machineconfigs"
extramanifests_dir="/Users/bpalm/Repositories/go/src/github.com/openshift-kni/telco-reference/telco-ran/configuration/extra-manifests-builder"

usage() {
  echo "Usage: $0 [-d source_dir] [-m machineconfig_dir] [-e extramanifests_dir] [-s severity[,severity...]] [-x]"
  echo "  -d  Source directory for YAMLs (default: complianceremediations)"
  echo "  -m  Destination directory for MachineConfigs (default: $machineconfig_dir)"
  echo "  -e  Destination directory for extra manifests (default: $extramanifests_dir)"
  echo "  -s  Comma-separated severities to include: high,medium,low (case-insensitive)"
  echo "      (Alias: -S)"
  echo "  -x  Execute automated apply + health/performance tests for created files"
  echo "  -h  Show this help message"
  exit 1
}

SEVERITY_FILTER=""
EXECUTE_TESTS=0

# Simple logger
log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

# Ensure required tools are available when executing tests
ensure_prereqs() {
  command -v oc >/dev/null 2>&1 || { echo "Error: 'oc' CLI is required to execute tests."; exit 1; }
  command -v yq >/dev/null 2>&1 || { echo "Error: 'yq' is required."; exit 1; }
}

# Capture basic performance metrics
capture_performance() {
  label="$1"
  out_dir="$2"
  mkdir -p "$out_dir"
  # Metrics API (optional on CRC); ignore failures silently
  oc adm top nodes >"$out_dir/${label}-top-nodes.txt" 2>/dev/null || true
  oc adm top pods -A >"$out_dir/${label}-top-pods.txt" 2>/dev/null || true
  # Non-metrics fallbacks always available
  oc get nodes -o wide >"$out_dir/${label}-nodes.txt" 2>/dev/null || true
  oc get pods -A -o wide >"$out_dir/${label}-pods.txt" 2>/dev/null || true
  oc get mcp -o wide >"$out_dir/${label}-mcp.txt" 2>/dev/null || true
}

# Cluster health checks: operators, nodes, pods
check_cluster_health() {
  out_dir="$1"
  mkdir -p "$out_dir"

  # Operators with potential issues
  oc get co -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.conditions[*]}{.type}{"="}{.status}{";"}{end}{"\n"}{end}' \
    | awk '($0 ~ /Degraded=True/ || $0 ~ /Progressing=True/ || $0 ~ /Available=False/){print $1}' | sort -u >"$out_dir/bad_operators.txt" 2>/dev/null || true

  # Nodes not Ready
  oc get nodes | awk 'NR>1 && $2!="Ready"{print $1, $2}' >"$out_dir/not_ready_nodes.txt" 2>/dev/null || true

  # Crashing pods
  oc get pods -A | grep -E 'CrashLoopBackOff|Error|ImagePullBackOff|CreateContainerError' \
    >"$out_dir/crashing_pods.txt" 2>/dev/null || true

  # MCPs not fully updated or degraded using tabular columns (works without metrics)
  oc get mcp | awk 'NR>1 && ($3!="True" || $5!="False"){print $1, "updated=" $3, "degraded=" $5}' \
    >"$out_dir/mcps_not_healthy.txt" 2>/dev/null || true

  # Machine Config Daemon pods not Ready
  oc -n openshift-machine-config-operator get pods 2>/dev/null | grep daemon | awk 'NR>=1 && $2!="1/1"{print $1, $2, $3}' \
    >"$out_dir/mcd_not_ready.txt" 2>/dev/null || true

  # Nodes with config drift (currentConfig != desiredConfig)
  oc get node -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.machineconfiguration\\.openshift\\.io/currentConfig}{" "}{.metadata.annotations.machineconfiguration\\.openshift\\.io/desiredConfig}{"\n"}{end}' 2>/dev/null \
    | awk 'NF==3 && $2!=$3{print $1, $2, $3}' >"$out_dir/nodes_config_drift.txt" 2>/dev/null || true
}



# Derive MCP role label from file (best-effort)
get_role_label() {
  path="$1"
  role=$(yq e '.metadata.labels["machineconfiguration.openshift.io/role"]' "$path" 2>/dev/null || echo "")
  if [[ -z "$role" || "$role" == "null" ]]; then
    base=$(basename "$path")
    if [[ "$base" == *"master"* ]]; then
      role="master"
    elif [[ "$base" == *"worker"* ]]; then
      role="worker"
    else
      role="worker"
    fi
  fi
  echo "$role"
}

# Apply a single file and wait for reconciliation where possible
apply_and_wait() {
  path="$1"
  kind=$(yq e '.kind' "$path" 2>/dev/null || echo "")
  log "Dry-run apply: $path"
  oc apply --dry-run=server -f "$path"
  log "Applying: $path"
  oc apply -f "$path"
  if [[ "$kind" == "MachineConfig" ]]; then
    role=$(get_role_label "$path")
    log "Waiting for MCP/$role to become Updated=True"
    oc wait mcp/"$role" --for=condition=Updated=True --timeout=45m
    oc get mcp "$role" -o wide || true
  elif [[ "$kind" == "APIServer" ]]; then
    log "Waiting for kube-apiserver operator Available=True"
    oc wait co/kube-apiserver --for=condition=Available=True --timeout=10m || true
  else
    oc get -f "$path" >/dev/null 2>&1 || true
  fi
}

# Run automated apply + tests
run_automated_tests() {
  ensure_prereqs
  if [[ -z "$new_paths" ]]; then
    log "No files to apply/test. Skipping."
    return 0
  fi

  ts=$(date -u +"%Y%m%dT%H%M%SZ")
  results_dir="test-results/$ts"
  mkdir -p "$results_dir"
  log "Capturing baseline performance metrics"
  capture_performance "baseline" "$results_dir"

  # Apply each file and wait as appropriate
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    apply_and_wait "$path"
  done <<<"$new_paths"

  log "Capturing post-change performance metrics"
  capture_performance "post" "$results_dir"

  log "Running cluster health checks"
  check_cluster_health "$results_dir"

  # Generate simple diffs
  diff -u "$results_dir/baseline-top-nodes.txt" "$results_dir/post-top-nodes.txt" >"$results_dir/diff-top-nodes.txt" 2>/dev/null || true
  diff -u "$results_dir/baseline-top-pods.txt" "$results_dir/post-top-pods.txt" >"$results_dir/diff-top-pods.txt" 2>/dev/null || true
  diff -u "$results_dir/baseline-mcp.txt" "$results_dir/post-mcp.txt" >"$results_dir/diff-mcp.txt" 2>/dev/null || true

  # Compose summary
  bad_ops_count=$(wc -l <"$results_dir/bad_operators.txt" 2>/dev/null || echo 0)
  not_ready_nodes_count=$(wc -l <"$results_dir/not_ready_nodes.txt" 2>/dev/null || echo 0)
  crashing_pods_count=$(wc -l <"$results_dir/crashing_pods.txt" 2>/dev/null || echo 0)
  mcps_not_healthy_count=$(wc -l <"$results_dir/mcps_not_healthy.txt" 2>/dev/null || echo 0)
  mcd_not_ready_count=$(wc -l <"$results_dir/mcd_not_ready.txt" 2>/dev/null || echo 0)
  nodes_config_drift_count=$(wc -l <"$results_dir/nodes_config_drift.txt" 2>/dev/null || echo 0)

  summary="Compliance apply + test: bad_operators=$bad_ops_count, not_ready_nodes=$not_ready_nodes_count, crashing_pods=$crashing_pods_count, mcps_not_healthy=$mcps_not_healthy_count, mcd_not_ready=$mcd_not_ready_count, nodes_config_drift=$nodes_config_drift_count. Results: $results_dir"
  echo "$summary"
}

while getopts "d:m:e:s:S:xh" opt; do
  case $opt in
    d) source_dir="$OPTARG" ;;
    m) machineconfig_dir="$OPTARG" ;;
    e) extramanifests_dir="$OPTARG" ;;
    s) SEVERITY_FILTER="$OPTARG" ;;
    S) SEVERITY_FILTER="$OPTARG" ;;
    x) EXECUTE_TESTS=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Precheck and create destination directories if missing
mkdir -p "$machineconfig_dir"
mkdir -p "$extramanifests_dir"

# Initialize a variable to keep track of newly created file paths
new_paths=""

# Normalize and validate severity filter if provided
if [[ -n "$SEVERITY_FILTER" ]]; then
	SEVERITY_FILTER=$(echo "$SEVERITY_FILTER" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
	IFS=',' read -r -a severity_list <<<"$SEVERITY_FILTER"
	for s in "${severity_list[@]}"; do
		if [[ "$s" != "high" && "$s" != "medium" && "$s" != "low" ]]; then
			echo "Error: Invalid severity '$s'. Allowed values: high, medium, low"
			exit 1
		fi
	done
	echo "Using severity filter: $SEVERITY_FILTER"
fi

# Build list of files to process
shopt -s nullglob
files_to_process=()

# Include top-level YAMLs; if severity filter provided, include only those whose
# filename contains one of the requested severities AND contains '-combo'
# (ensures we only pick combined outputs and not the originals)
for f in "$source_dir"/*.yaml; do
	if [[ -n "$SEVERITY_FILTER" ]]; then
		base_name=$(basename "$f")
		include=0
		for s in "${severity_list[@]}"; do
			if [[ "$base_name" == *"-$s-"* || "$base_name" == *"-$s.yaml" ]]; then
				# Only include if it's a combo output
				if [[ "$base_name" == *"-combo.yaml" ]]; then
				include=1
				break
				fi
			fi
		done
		if [[ $include -eq 0 ]]; then
			continue
		fi
	fi
	files_to_process+=("$f")
done

# If severity filter provided, include -combo.yaml files inside matching
# severity-named subdirectories directly under source_dir
if [[ -n "$SEVERITY_FILTER" ]]; then
	for s in "${severity_list[@]}"; do
		for f in "$source_dir/$s"/*.yaml; do
			base_name=$(basename "$f")
			if [[ "$base_name" == *"-combo.yaml" ]]; then
				files_to_process+=("$f")
			fi
		done
	done
fi

# Loop through the prepared list of YAML files
for file in "${files_to_process[@]}"; do
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
		# Determine the role (master or worker) based on the filename or file contents
		role="unknown"
		
		# First check filename (for backward compatibility)
		if [[ "$base_name" == *"master"* ]]; then
			role="master"
		elif [[ "$base_name" == *"worker"* ]]; then
			role="worker"
		else
			# Check the first 3 lines for combined file comments
			first_lines=$(head -n 3 "$file")
			has_master=$(echo "$first_lines" | grep -c "master" || true)
			has_worker=$(echo "$first_lines" | grep -c "worker" || true)
			
			if [[ $has_master -gt 0 && $has_worker -gt 0 ]]; then
				# If both master and worker are mentioned, use worker
				role="worker"
			elif [[ $has_master -gt 0 ]]; then
				role="master"
			elif [[ $has_worker -gt 0 ]]; then
				role="worker"
			else
				# Fallback: check entire file content
				if grep -q "master" "$file"; then
					role="master"
				elif grep -q "worker" "$file"; then
					role="worker"
				else
					# Default for files with no role indication
					role="worker"
				fi
			fi
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
		if [[ "$kind" == "APIServer" ]]; then
			# Always set metadata.name to 'cluster' for APIServer
			yq ".metadata.name = \"cluster\"" "$file" >"$kind_dir/$new_name"
		else
			# Update metadata.name as before
			yq ".metadata.name = \"$metadata_name\"" "$file" >"$kind_dir/$new_name"
		fi
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

	# Generate testing plan markdown for the created files
	plan_file="testing-plan.md"
	ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	# Header and prerequisites
	{
		echo "## Compliance YAML Testing Plan"
		echo
		echo "Generated: $ts"
		echo
		echo "- **Prerequisites**:"
		echo "  - **Cluster access**: logged in with a user that can manage cluster-scoped resources"
		echo "  - **Tools**: 'oc' (or 'kubectl'), 'yq'"
		echo "  - **Context**: points to the target cluster"
		echo
		echo "### Files under test"
		while IFS= read -r path; do
			kind=$(yq e '.kind' "$path" 2>/dev/null || echo "Unknown")
			echo "- $path ($kind)"
		done <<<"$new_paths"
		echo
		echo "### 1) Capture baseline performance"
		echo "Save baseline metrics before applying changes."
		echo '```bash'
		echo "mkdir -p test-results"
		echo "oc adm top nodes > test-results/baseline-top-nodes.txt"
		echo "oc adm top pods -A > test-results/baseline-top-pods.txt"
		echo "oc get mcp -o wide > test-results/baseline-mcp.txt || true"
		echo '```'
		echo
		echo "### 2) Deployment validation per file"
		echo "For each file below, first perform a server-side dry-run, then apply."
	} >"$plan_file"

	# Per-file deployment steps
	while IFS= read -r path; do
		kind=$(yq e '.kind' "$path" 2>/dev/null || echo "Unknown")
		role_label=$(yq e '.metadata.labels."machineconfiguration.openshift.io/role"' "$path" 2>/dev/null || true)
		name=$(yq e '.metadata.name' "$path" 2>/dev/null || true)
		{
			echo
			echo "#### $path ($kind)"
			echo '```bash'
			echo "# Validate schema and permissions without persisting"
			echo "oc apply --dry-run=server -f '$path'"
			echo
			echo "# Apply"
			echo "oc apply -f '$path'"
			if [[ "$kind" == "MachineConfig" ]]; then
				# If role is known, provide targeted wait; otherwise suggest watching all pools
				if [[ -n "$role_label" && "$role_label" != "null" ]]; then
					echo
					echo "# Wait for MachineConfigPool to reconcile"
					echo "oc wait mcp/$role_label --for=condition=Updated=True --timeout=45m"
					echo "oc get mcp $role_label -o wide"
				else
					echo
					echo "# Wait for MachineConfigPools to reconcile (role unknown)"
					echo "oc get mcp -o wide"
					echo "# Optionally monitor: oc get mcp --watch"
				fi
			else
				echo
				echo "# Verify the applied resource exists"
				echo "oc get -f '$path'"
				# For cluster operators like APIServer, add a generic availability check
				if [[ "$kind" == "APIServer" ]]; then
					echo "# For APIServer changes, confirm operator availability"
					echo "oc wait co/kube-apiserver --for=condition=Available=True --timeout=10m || true"
				fi
			fi
			echo '```'
		} >>"$plan_file"
	done <<<"$new_paths"

	# Post-change performance capture and comparison guidance
	{
		echo
		echo "### 3) Capture post-change performance"
		echo "After all changes reconcile, capture the same metrics."
		echo '```bash'
		echo "oc adm top nodes > test-results/post-top-nodes.txt"
		echo "oc adm top pods -A > test-results/post-top-pods.txt"
		echo "oc get mcp -o wide > test-results/post-mcp.txt || true"
		echo '```'
		echo
		echo "### 4) Compare baseline vs post-change"
		echo "Review differences for potential performance impact."
		echo '```bash'
		echo "diff -u test-results/baseline-top-nodes.txt test-results/post-top-nodes.txt || true"
		echo "diff -u test-results/baseline-top-pods.txt test-results/post-top-pods.txt || true"
		echo "diff -u test-results/baseline-mcp.txt test-results/post-mcp.txt || true"
		echo '```'
		echo
		echo "### 5) Optional rollback"
		echo "If needed, revert applied changes:"
		echo '```bash'
		while IFS= read -r path; do
			echo "oc delete -f '$path' || true"
		done <<<"$new_paths"
		echo '```'
	} >>"$plan_file"

	echo "A testing plan has been generated at '$plan_file'."
else
	echo "No new file paths were created."
fi

echo "All YAML files have been organized and copied to their respective directories."

# Execute automated tests if requested
if [[ $EXECUTE_TESTS -eq 1 ]]; then
	log "Automated execution requested (-x). Starting apply + health/performance tests."
	run_automated_tests
fi
