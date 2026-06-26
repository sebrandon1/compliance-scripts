#!/bin/bash
# detect-mc-conflicts.sh - Detect conflicts between MachineConfig YAMLs
#
# Scans MachineConfig files and reports:
#   - File path conflicts (multiple MCs writing to the same file)
#   - Ignition spec version mismatches (different versions for the same role)
#   - Sysctl value conflicts (same key with different values)
#   - Kernel argument conflicts (same key with different values)
# Optionally cross-references tracking.json to show which
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
	echo "Detect conflicts between MachineConfig YAML files."
	echo "Checks: file path overlaps, Ignition version mismatches,"
	echo "sysctl value conflicts, and kernel argument conflicts."
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

TMP_DIR=$(make_temp_dir)

PATHMAP="$TMP_DIR/pathmap.tsv"
IGNITION_MAP="$TMP_DIR/ignition.tsv"
SYSCTL_MAP="$TMP_DIR/sysctl.tsv"
KARGS_MAP="$TMP_DIR/kargs.tsv"
: >"$PATHMAP"
: >"$IGNITION_MAP"
: >"$SYSCTL_MAP"
: >"$KARGS_MAP"

log_info "Scanning for MachineConfig conflicts..."

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

		# Collect Ignition version
		ign_ver=$(yq e '.spec.config.ignition.version' "$yaml_file" 2>/dev/null || echo "")
		if [[ -n "$ign_ver" && "$ign_ver" != "null" ]]; then
			printf "%s\t%s\t%s\n" "$ign_ver" "$role" "$mc_base" >>"$IGNITION_MAP"
		fi

		# Collect sysctl values from data:, encoded sysctl.d files
		file_paths=$(yq e '.spec.config.storage.files[].path' "$yaml_file" 2>/dev/null || true)
		if [[ -n "$file_paths" ]]; then
			while IFS= read -r fp; do
				[[ -z "$fp" || "$fp" == "null" ]] && continue
				printf "%s\t%s\t%s\n" "$fp" "$role" "$mc_base" >>"$PATHMAP"

				# Extract sysctl key=value pairs from sysctl.d files
				if [[ "$fp" == /etc/sysctl.d/* || "$fp" == /etc/sysctl.conf ]]; then
					source_data=$(yq e ".spec.config.storage.files[] | select(.path == \"$fp\") | .contents.source" "$yaml_file" 2>/dev/null || true)
					if [[ "$source_data" == data:,* ]]; then
						decoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.unquote(sys.argv[1][6:]))" "$source_data" 2>/dev/null || true)
						if [[ -n "$decoded" ]]; then
							while IFS= read -r line; do
								line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
								[[ -z "$line" ]] && continue
								key=$(echo "$line" | cut -d'=' -f1 | tr -d ' ')
								val=$(echo "$line" | cut -d'=' -f2- | tr -d ' ')
								[[ -z "$key" ]] && continue
								printf "%s\t%s\t%s\t%s\n" "$key" "$val" "$role" "$mc_base" >>"$SYSCTL_MAP"
							done <<<"$decoded"
						fi
					fi
				fi
			done <<<"$file_paths"
		fi

		# Collect kernel arguments
		kargs=$(yq e '.spec.kernelArguments[]' "$yaml_file" 2>/dev/null || true)
		if [[ -n "$kargs" ]]; then
			while IFS= read -r karg; do
				[[ -z "$karg" || "$karg" == "null" ]] && continue
				key=$(echo "$karg" | cut -d'=' -f1)
				val=$(echo "$karg" | cut -s -d'=' -f2-)
				printf "%s\t%s\t%s\t%s\n" "$key" "${val:-__flag__}" "$role" "$mc_base" >>"$KARGS_MAP"
			done <<<"$kargs"
		fi
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

# --- Ignition version mismatch detection ---
IGNITION_CONFLICT_COUNT=0

if [[ -s "$IGNITION_MAP" ]]; then
	# Check per-role: all MCs for the same role should use the same Ignition version
	sort -u "$IGNITION_MAP" | awk -F'\t' '{print $2}' | sort -u | while IFS= read -r role; do
		versions=$(awk -F'\t' -v r="$role" '$2==r {print $1}' "$IGNITION_MAP" | sort -u)
		ver_count=$(echo "$versions" | wc -l | tr -d ' ')
		if [[ "$ver_count" -gt 1 ]]; then
			IGNITION_CONFLICT_COUNT=$((IGNITION_CONFLICT_COUNT + 1))
			echo ""
			log_error "IGNITION VERSION MISMATCH (role: $role)"
			echo "  Multiple Ignition spec versions found:"
			while IFS= read -r ver; do
				mc_files=$(awk -F'\t' -v r="$role" -v v="$ver" '$1==v && $2==r {print $3}' "$IGNITION_MAP" | sort -u)
				echo "    $ver:"
				while IFS= read -r mc; do
					echo "      - $mc"
				done <<<"$mc_files"
			done <<<"$versions"
			echo "  All MachineConfigs for a role should use the same Ignition version."
		fi
	done
	# Re-count outside subshell
	IGNITION_CONFLICT_COUNT=$(sort -u "$IGNITION_MAP" | awk -F'\t' '{print $2}' | sort -u | while IFS= read -r role; do
		ver_count=$(awk -F'\t' -v r="$role" '$2==r {print $1}' "$IGNITION_MAP" | sort -u | wc -l | tr -d ' ')
		[[ "$ver_count" -gt 1 ]] && echo 1
	done | wc -l | tr -d ' ')
fi

# --- Sysctl value conflict detection ---
SYSCTL_CONFLICT_COUNT=0

if [[ -s "$SYSCTL_MAP" ]]; then
	# Find sysctl keys with conflicting values for the same role
	sort -u "$SYSCTL_MAP" | awk -F'\t' '{print $1 "\t" $3}' | sort -u | while IFS=$'\t' read -r key role; do
		values=$(awk -F'\t' -v k="$key" -v r="$role" '$1==k && $3==r {print $2}' "$SYSCTL_MAP" | sort -u)
		val_count=$(echo "$values" | wc -l | tr -d ' ')
		if [[ "$val_count" -gt 1 ]]; then
			echo ""
			log_error "SYSCTL CONFLICT: $key (role: $role)"
			echo "  Conflicting values set by different MachineConfigs:"
			while IFS= read -r val; do
				mc_files=$(awk -F'\t' -v k="$key" -v v="$val" -v r="$role" '$1==k && $2==v && $3==r {print $4}' "$SYSCTL_MAP" | sort -u)
				echo "    $key=$val"
				while IFS= read -r mc; do
					echo "      - $mc"
				done <<<"$mc_files"
			done <<<"$values"
		fi
	done
	SYSCTL_CONFLICT_COUNT=$(sort -u "$SYSCTL_MAP" | awk -F'\t' '{print $1 "\t" $3}' | sort -u | while IFS=$'\t' read -r key role; do
		val_count=$(awk -F'\t' -v k="$key" -v r="$role" '$1==k && $3==r {print $2}' "$SYSCTL_MAP" | sort -u | wc -l | tr -d ' ')
		[[ "$val_count" -gt 1 ]] && echo 1
	done | wc -l | tr -d ' ')
fi

# --- Kernel argument conflict detection ---
KARGS_CONFLICT_COUNT=0

if [[ -s "$KARGS_MAP" ]]; then
	sort -u "$KARGS_MAP" | awk -F'\t' '{print $1 "\t" $3}' | sort -u | while IFS=$'\t' read -r key role; do
		values=$(awk -F'\t' -v k="$key" -v r="$role" '$1==k && $3==r {print $2}' "$KARGS_MAP" | sort -u)
		val_count=$(echo "$values" | wc -l | tr -d ' ')
		if [[ "$val_count" -gt 1 ]]; then
			echo ""
			log_error "KERNEL ARGUMENT CONFLICT: $key (role: $role)"
			echo "  Conflicting values set by different MachineConfigs:"
			while IFS= read -r val; do
				display_val="$val"
				[[ "$val" == "__flag__" ]] && display_val="(no value / flag-only)"
				mc_files=$(awk -F'\t' -v k="$key" -v v="$val" -v r="$role" '$1==k && $2==v && $3==r {print $4}' "$KARGS_MAP" | sort -u)
				echo "    $key=$display_val"
				while IFS= read -r mc; do
					echo "      - $mc"
				done <<<"$mc_files"
			done <<<"$values"
		fi
	done
	KARGS_CONFLICT_COUNT=$(sort -u "$KARGS_MAP" | awk -F'\t' '{print $1 "\t" $3}' | sort -u | while IFS=$'\t' read -r key role; do
		val_count=$(awk -F'\t' -v k="$key" -v r="$role" '$1==k && $3==r {print $2}' "$KARGS_MAP" | sort -u | wc -l | tr -d ' ')
		[[ "$val_count" -gt 1 ]] && echo 1
	done | wc -l | tr -d ' ')
fi

TOTAL_CONFLICTS=$((CONFLICT_COUNT + IGNITION_CONFLICT_COUNT + SYSCTL_CONFLICT_COUNT + KARGS_CONFLICT_COUNT))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CONFLICT DETECTION SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  %-25s %d\n" "Files scanned:" "$FILE_COUNT"
printf "  %-25s %d\n" "MachineConfigs found:" "$MC_COUNT"
printf "  %-25s %d\n" "File path conflicts:" "$CONFLICT_COUNT"
printf "  %-25s %d\n" "Ignition version mismatches:" "$IGNITION_CONFLICT_COUNT"
printf "  %-25s %d\n" "Sysctl value conflicts:" "$SYSCTL_CONFLICT_COUNT"
printf "  %-25s %d\n" "Kernel arg conflicts:" "$KARGS_CONFLICT_COUNT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $TOTAL_CONFLICTS -gt 0 ]]; then
	echo ""
	if [[ $CONFLICT_COUNT -gt 0 ]]; then
		log_warn "Conflicting paths:"
		echo "$CONFLICT_PATHS" | while IFS= read -r p; do
			[[ -z "$p" ]] && continue
			echo "  - $p"
		done
		log_warn "MachineConfigs targeting the same file path will overwrite each other."
		log_warn "Only the last-applied MC's content will be effective."
		log_warn "Consider merging conflicting MCs into a single file per path."
	fi
	if [[ $IGNITION_CONFLICT_COUNT -gt 0 ]]; then
		echo ""
		log_warn "Ignition version mismatches can cause MachineConfig rendering failures."
		log_warn "Standardize all MCs to the same Ignition spec version (e.g., 3.5.0 for OCP 4.22+)."
	fi
	if [[ $SYSCTL_CONFLICT_COUNT -gt 0 ]]; then
		echo ""
		log_warn "Conflicting sysctl values: only the last-applied value takes effect."
		log_warn "Merge conflicting sysctls into a single MachineConfig."
	fi
	if [[ $KARGS_CONFLICT_COUNT -gt 0 ]]; then
		echo ""
		log_warn "Conflicting kernel arguments: the MCO merges kernel args from all MCs,"
		log_warn "but duplicate keys with different values produce undefined behavior."
	fi
	exit 1
fi

echo ""
log_success "No conflicts detected."
exit 0
