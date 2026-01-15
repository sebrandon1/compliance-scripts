#!/bin/bash
# validate-machineconfig.sh - Validate MachineConfig YAML files before applying
#
# Usage: ./scripts/validate-machineconfig.sh [OPTIONS] <file.yaml> [file2.yaml ...]
#
# Options:
#   -d, --dir          Validate all YAML files in directory
#   --strict           Enable strict mode (fail on warnings)
#   --show-diff        Show diff against current cluster state
#   -h, --help         Show this help message

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
	# shellcheck source=../lib/common.sh
	source "$SCRIPT_DIR/lib/common.sh"
else
	# Fallback if common.sh doesn't exist
	log_info() { echo "[INFO] $*"; }
	log_warn() { echo "[WARN] $*"; }
	log_error() { echo "[ERROR] $*" >&2; }
	log_success() { echo "[SUCCESS] $*"; }
	require_cmd() { for cmd in "$@"; do command -v "$cmd" &>/dev/null || {
		echo "Error: '$cmd' not found"
		exit 1
	}; done; }
fi

# Check required dependencies
require_cmd yq

STRICT_MODE=false
SHOW_DIFF=false
VALIDATE_DIR=""
FILES=()

usage() {
	echo "Usage: $0 [OPTIONS] <file.yaml> [file2.yaml ...]"
	echo ""
	echo "Validate MachineConfig YAML files before applying to a cluster."
	echo ""
	echo "Options:"
	echo "  -d, --dir         Validate all YAML files in a directory"
	echo "  --strict          Enable strict mode (warnings become errors)"
	echo "  --show-diff       Show diff against current cluster state (requires oc)"
	echo "  -h, --help        Show this help message"
	echo ""
	echo "Checks performed:"
	echo "  - Valid YAML syntax"
	echo "  - Required MachineConfig fields (apiVersion, kind, spec)"
	echo "  - Ignition version compatibility"
	echo "  - Role label presence (master/worker)"
	echo "  - File path validation"
	echo "  - Content encoding verification"
	echo ""
	echo "Examples:"
	echo "  $0 myconfig.yaml"
	echo "  $0 -d ./complianceremediations/"
	echo "  $0 --strict --show-diff myconfig.yaml"
	exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	-d | --dir)
		VALIDATE_DIR="$2"
		shift 2
		;;
	--strict)
		STRICT_MODE=true
		shift
		;;
	--show-diff)
		SHOW_DIFF=true
		shift
		;;
	-h | --help)
		usage
		;;
	-*)
		log_error "Unknown option: $1"
		usage
		;;
	*)
		FILES+=("$1")
		shift
		;;
	esac
done

# Collect files to validate
if [[ -n "$VALIDATE_DIR" ]]; then
	if [[ ! -d "$VALIDATE_DIR" ]]; then
		log_error "Directory not found: $VALIDATE_DIR"
		exit 1
	fi
	while IFS= read -r -d '' file; do
		FILES+=("$file")
	done < <(find "$VALIDATE_DIR" -name '*.yaml' -type f -print0)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
	log_error "No files specified. Use -d <dir> or provide file paths."
	usage
fi

# Counters
TOTAL=0
PASSED=0
WARNINGS=0
FAILED=0

# Validate a single MachineConfig file
validate_machineconfig() {
	local file="$1"
	local issues=()
	local warnings=()

	TOTAL=$((TOTAL + 1))

	# Check file exists
	if [[ ! -f "$file" ]]; then
		log_error "File not found: $file"
		FAILED=$((FAILED + 1))
		return 1
	fi

	log_info "Validating: $file"

	# Check YAML syntax
	if ! yq e '.' "$file" >/dev/null 2>&1; then
		issues+=("Invalid YAML syntax")
	fi

	# Check kind
	local kind
	kind=$(yq e '.kind' "$file" 2>/dev/null || echo "")
	if [[ "$kind" != "MachineConfig" ]]; then
		if [[ "$kind" == "null" || -z "$kind" ]]; then
			issues+=("Missing 'kind' field")
		else
			warnings+=("Not a MachineConfig (kind: $kind)")
			log_warn "  Skipping non-MachineConfig file (kind: $kind)"
			WARNINGS=$((WARNINGS + 1))
			return 0
		fi
	fi

	# Check apiVersion
	local api_version
	api_version=$(yq e '.apiVersion' "$file" 2>/dev/null || echo "")
	if [[ "$api_version" == "null" || -z "$api_version" ]]; then
		issues+=("Missing 'apiVersion' field")
	elif [[ "$api_version" != "machineconfiguration.openshift.io/v1" ]]; then
		warnings+=("Unusual apiVersion: $api_version (expected machineconfiguration.openshift.io/v1)")
	fi

	# Check metadata.name
	local mc_name
	mc_name=$(yq e '.metadata.name' "$file" 2>/dev/null || echo "")
	if [[ "$mc_name" == "null" || -z "$mc_name" ]]; then
		issues+=("Missing 'metadata.name' field")
	fi

	# Check role label
	local role
	role=$(yq e '.metadata.labels["machineconfiguration.openshift.io/role"]' "$file" 2>/dev/null || echo "")
	if [[ "$role" == "null" || -z "$role" ]]; then
		warnings+=("Missing role label (machineconfiguration.openshift.io/role)")
	elif [[ "$role" != "master" && "$role" != "worker" ]]; then
		warnings+=("Unusual role label: $role (expected master or worker)")
	fi

	# Check spec.config exists
	local has_config
	has_config=$(yq e '.spec.config' "$file" 2>/dev/null || echo "")
	if [[ "$has_config" == "null" || -z "$has_config" ]]; then
		issues+=("Missing 'spec.config' section")
	fi

	# Check ignition version
	local ignition_version
	ignition_version=$(yq e '.spec.config.ignition.version' "$file" 2>/dev/null || echo "")
	if [[ "$ignition_version" == "null" || -z "$ignition_version" ]]; then
		warnings+=("Missing ignition version (recommended: 3.2.0 or later)")
	else
		# Check for supported versions (3.x.x)
		if [[ ! "$ignition_version" =~ ^3\.[0-9]+\.[0-9]+$ ]]; then
			warnings+=("Unusual ignition version: $ignition_version (expected 3.x.x)")
		fi
	fi

	# Check files in storage section
	local file_count
	file_count=$(yq e '.spec.config.storage.files | length' "$file" 2>/dev/null || echo "0")
	if [[ "$file_count" -gt 0 ]]; then
		# Validate each file entry
		for i in $(seq 0 $((file_count - 1))); do
			local file_path
			file_path=$(yq e ".spec.config.storage.files[$i].path" "$file" 2>/dev/null || echo "")
			if [[ -z "$file_path" || "$file_path" == "null" ]]; then
				issues+=("File entry $i missing 'path' field")
			elif [[ ! "$file_path" =~ ^/ ]]; then
				issues+=("File path must be absolute: $file_path")
			fi

			# Check for content source
			local source
			source=$(yq e ".spec.config.storage.files[$i].contents.source" "$file" 2>/dev/null || echo "")
			if [[ -z "$source" || "$source" == "null" ]]; then
				warnings+=("File entry $i ($file_path): missing contents.source")
			elif [[ ! "$source" =~ ^data: ]]; then
				warnings+=("File entry $i ($file_path): unusual source format (expected data: URI)")
			fi
		done
	fi

	# Show diff against cluster if requested
	if [[ "$SHOW_DIFF" == "true" && -n "$mc_name" && "$mc_name" != "null" ]]; then
		if command -v oc &>/dev/null && oc whoami &>/dev/null 2>&1; then
			log_info "  Checking cluster diff for $mc_name..."
			local current_config
			if current_config=$(oc get machineconfig "$mc_name" -o yaml 2>/dev/null); then
				local diff_output
				diff_output=$(diff -u <(echo "$current_config" | yq e 'del(.metadata.creationTimestamp, .metadata.generation, .metadata.resourceVersion, .metadata.uid, .status)' -) "$file" 2>/dev/null || true)
				if [[ -n "$diff_output" ]]; then
					echo "  Diff against cluster:"
					echo "$diff_output" | sed 's/^/    /'
				else
					log_info "  No differences from cluster version"
				fi
			else
				log_info "  MachineConfig '$mc_name' not found in cluster (new resource)"
			fi
		else
			log_warn "  Cannot show diff: not connected to cluster"
		fi
	fi

	# Report results
	if [[ ${#issues[@]} -gt 0 ]]; then
		log_error "  FAILED - ${#issues[@]} error(s):"
		for issue in "${issues[@]}"; do
			echo "    - $issue"
		done
		FAILED=$((FAILED + 1))
		return 1
	fi

	if [[ ${#warnings[@]} -gt 0 ]]; then
		log_warn "  ${#warnings[@]} warning(s):"
		for warning in "${warnings[@]}"; do
			echo "    - $warning"
		done
		WARNINGS=$((WARNINGS + 1))
		if [[ "$STRICT_MODE" == "true" ]]; then
			log_error "  FAILED (strict mode - warnings treated as errors)"
			FAILED=$((FAILED + 1))
			return 1
		fi
	fi

	log_success "  PASSED"
	PASSED=$((PASSED + 1))
	return 0
}

# Validate all files
echo ""
for file in "${FILES[@]}"; do
	validate_machineconfig "$file" || true
	echo ""
done

# Print summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VALIDATION SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  %-20s %d\n" "Total files:" "$TOTAL"
printf "  %-20s %d\n" "Passed:" "$PASSED"
printf "  %-20s %d\n" "With warnings:" "$WARNINGS"
printf "  %-20s %d\n" "Failed:" "$FAILED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAILED -gt 0 ]]; then
	exit 1
fi
exit 0
