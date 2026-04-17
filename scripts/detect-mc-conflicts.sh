#!/bin/bash
# detect-mc-conflicts.sh - Detect file path conflicts between MachineConfig YAMLs
#
# Scans MachineConfig files and reports when multiple MCs target the same
# file path. Optionally cross-references tracking.json to show which
# remediation groups are involved.
#
# Usage: ./scripts/detect-mc-conflicts.sh [OPTIONS] [DIR ...]
#
# Options:
#   -t, --tracking FILE   Path to tracking.json for group resolution
#   -v, --verbose         Show all file paths, not just conflicts
#   -h, --help            Show this help message
#
# Examples:
#   ./scripts/detect-mc-conflicts.sh complianceremediations/
#   ./scripts/detect-mc-conflicts.sh -t docs/_data/tracking.json output/machineconfigs/
#   ./scripts/detect-mc-conflicts.sh dir1/ dir2/ dir3/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_cmd yq

TRACKING_FILE=""
VERBOSE=false
DIRS=()

usage() {
	echo "Usage: $0 [OPTIONS] [DIR ...]"
	echo ""
	echo "Detect file path conflicts between MachineConfig YAML files."
	echo ""
	echo "Options:"
	echo "  -t, --tracking FILE   Path to tracking.json for group resolution"
	echo "  -v, --verbose         Show all file paths, not just conflicts"
	echo "  -h, --help            Show this help message"
	echo ""
	echo "If no directories are specified, defaults to complianceremediations/"
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-t | --tracking)
		TRACKING_FILE="$2"
		shift 2
		;;
	-v | --verbose)
		VERBOSE=true
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
		DIRS+=("$1")
		shift
		;;
	esac
done

if [[ ${#DIRS[@]} -eq 0 ]]; then
	DIRS=("complianceremediations")
fi

for dir in "${DIRS[@]}"; do
	if [[ ! -d "$dir" ]]; then
		log_error "Directory not found: $dir"
		exit 1
	fi
done

if [[ -n "$TRACKING_FILE" && ! -f "$TRACKING_FILE" ]]; then
	log_error "Tracking file not found: $TRACKING_FILE"
	exit 1
fi

if [[ -n "$TRACKING_FILE" ]]; then
	require_cmd jq
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PATHMAP="$TMP_DIR/pathmap.tsv"
: >"$PATHMAP"

log_info "Scanning for MachineConfig file path conflicts..."

FILE_COUNT=0
MC_COUNT=0

for dir in "${DIRS[@]}"; do
	while IFS= read -r -d '' yaml_file; do
		FILE_COUNT=$((FILE_COUNT + 1))

		kind=$(yq e '.kind' "$yaml_file" 2>/dev/null || echo "")
		[[ "$kind" != "MachineConfig" ]] && continue

		MC_COUNT=$((MC_COUNT + 1))
		mc_base=$(basename "$yaml_file")
		role=$(get_node_role "$yaml_file")

		file_paths=$(yq e '.spec.config.storage.files[].path' "$yaml_file" 2>/dev/null || true)
		[[ -z "$file_paths" ]] && continue

		while IFS= read -r fp; do
			[[ -z "$fp" || "$fp" == "null" ]] && continue
			printf "%s\t%s\t%s\n" "$fp" "$role" "$mc_base" >>"$PATHMAP"
		done <<<"$file_paths"
	done < <(find "$dir" -name '*.yaml' -type f -print0)
done

log_info "Scanned $FILE_COUNT files, found $MC_COUNT MachineConfigs"

resolve_group() {
	local mc_file="$1"
	[[ -z "$TRACKING_FILE" ]] && return

	local check_name group title
	for pattern in \
		's/^[0-9]+-//; s/-(high|medium|low)(-combo)?\.yaml$//; s/-combo\.yaml$//; s/\.yaml$//' \
		's/^[0-9]+-//; s/-combo\.yaml$//; s/\.yaml$//' \
		's/^[0-9]+-//; s/-(high|medium|low)\.yaml$//; s/\.yaml$//'; do
		check_name=$(echo "$mc_file" | sed -E "$pattern")
		group=$(jq -r --arg name "$check_name" '.remediations[$name].group // empty' "$TRACKING_FILE" 2>/dev/null || true)
		if [[ -n "$group" ]]; then
			title=$(jq -r --arg g "$group" '.groups[$g].title // empty' "$TRACKING_FILE" 2>/dev/null || true)
			if [[ -n "$title" ]]; then
				echo "$group ($title)"
			else
				echo "$group"
			fi
			return
		fi
	done
}

CONFLICT_COUNT=0
CONFLICT_PATHS=""

sort "$PATHMAP" | awk -F'\t' '{print $1 "\t" $2}' | sort -u >"$TMP_DIR/keys.tsv"

while IFS=$'\t' read -r file_path role; do
	mc_files=$(awk -F'\t' -v fp="$file_path" -v r="$role" '$1==fp && $2==r {print $3}' "$PATHMAP" | sort -u)
	mc_count=$(echo "$mc_files" | wc -l | tr -d ' ')

	if [[ "$mc_count" -gt 1 ]]; then
		CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
		CONFLICT_PATHS="${CONFLICT_PATHS}${file_path}"$'\n'

		echo ""
		log_error "CONFLICT: $file_path (role: $role)"
		echo "  Written by $mc_count MachineConfigs:"
		while IFS= read -r mc; do
			[[ -z "$mc" ]] && continue
			group_info=$(resolve_group "$mc")
			if [[ -n "$group_info" ]]; then
				echo "    - $mc  [group: $group_info]"
			else
				echo "    - $mc"
			fi
		done <<<"$mc_files"
	elif [[ "$VERBOSE" == "true" ]]; then
		mc=$(echo "$mc_files" | head -1)
		group_info=$(resolve_group "$mc")
		if [[ -n "$group_info" ]]; then
			echo "  OK: $file_path (role: $role) <- $mc [$group_info]"
		else
			echo "  OK: $file_path (role: $role) <- $mc"
		fi
	fi
done <"$TMP_DIR/keys.tsv"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CONFLICT DETECTION SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  %-25s %d\n" "Files scanned:" "$FILE_COUNT"
printf "  %-25s %d\n" "MachineConfigs found:" "$MC_COUNT"
printf "  %-25s %d\n" "File path conflicts:" "$CONFLICT_COUNT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $CONFLICT_COUNT -gt 0 ]]; then
	echo ""
	log_warn "Conflicting paths:"
	echo "$CONFLICT_PATHS" | while IFS= read -r p; do
		[[ -z "$p" ]] && continue
		echo "  - $p"
	done
	echo ""
	log_warn "MachineConfigs targeting the same file path will overwrite each other."
	log_warn "Only the last-applied MC's content will be effective."
	log_warn "Consider merging conflicting MCs into a single file per path."
	exit 1
fi

echo ""
log_success "No file path conflicts detected."
exit 0
