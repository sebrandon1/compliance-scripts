#!/bin/bash
# verify-all-groups.sh - Apply all remediation groups and verify scan results
#
# Applies all tracked remediation groups from telco-reference to the connected
# cluster, waits for MCP rollout, re-scans, and produces a before/after report
# showing which checks flipped FAIL to PASS.
#
# Usage: ./scripts/verify-all-groups.sh [OPTIONS]
#
# Options:
#   --skip-baseline        Skip baseline scan export (use existing results)
#   --skip-apply           Skip applying MCs (just re-scan and diff)
#   --groups G1,G2,...     Only apply specific groups (default: all with compare branches)
#   --output-dir DIR       Output directory for artifacts (default: test-results/<timestamp>)
#   --dry-run              Download MCs but don't apply them
#   -h, --help             Show this help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_cmd oc jq yq curl
require_cluster

TRACKING="$SCRIPT_DIR/docs/_data/tracking.json"
SKIP_BASELINE=false
SKIP_APPLY=false
GROUP_FILTER=""
OUTPUT_DIR=""
DRY_RUN=false

usage() {
	echo "Usage: $0 [OPTIONS]"
	echo ""
	echo "Apply all remediation groups and verify compliance scan results."
	echo ""
	echo "Options:"
	echo "  --skip-baseline        Skip baseline scan export (use existing results)"
	echo "  --skip-apply           Skip applying MCs (just re-scan and diff)"
	echo "  --groups G1,G2,...     Only apply specific groups (default: all with compare branches)"
	echo "  --output-dir DIR       Output directory for artifacts (default: test-results/<timestamp>)"
	echo "  --dry-run              Download MCs but don't apply them"
	echo "  -h, --help             Show this help message"
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--skip-baseline)
		SKIP_BASELINE=true
		shift
		;;
	--skip-apply)
		SKIP_APPLY=true
		shift
		;;
	--groups)
		GROUP_FILTER="$2"
		shift 2
		;;
	--output-dir)
		OUTPUT_DIR="$2"
		shift 2
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	-h | --help)
		usage
		;;
	*)
		log_error "Unknown option: $1"
		usage
		;;
	esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
	OUTPUT_DIR="test-results/$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$OUTPUT_DIR/machineconfigs"

HARDENING_PATHS=(
	"telco-ran/configuration/kube-compare-reference/informational/hardening"
	"telco-ran/configuration/reference-crs/informational/hardening"
)

build_group_list() {
	if [[ -n "$GROUP_FILTER" ]]; then
		echo "$GROUP_FILTER" | tr ',' '\n' | tr '[:lower:]' '[:upper:]'
	else
		jq -r '.groups | to_entries[] | select(.value.compare != null) | .key' "$TRACKING"
	fi
}

fetch_group_mcs() {
	local group_id="$1"
	local compare="$2"
	local mc_dir="$OUTPUT_DIR/machineconfigs/$group_id"
	mkdir -p "$mc_dir"

	local mc_files=""
	for path in "${HARDENING_PATHS[@]}"; do
		mc_files=$(curl -fsSL "https://api.github.com/repos/sebrandon1/telco-reference/contents/${path}?ref=${compare}" 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)
		if [[ -n "$mc_files" ]]; then
			local files_url="https://raw.githubusercontent.com/sebrandon1/telco-reference/${compare}/${path}"
			for mc_file in $mc_files; do
				curl -fsSL "${files_url}/${mc_file}" -o "${mc_dir}/${mc_file}" 2>/dev/null || true
			done
			echo "$mc_files"
			return 0
		fi
	done
	return 1
}

wait_for_scans() {
	local label="$1"
	log_info "Waiting for $label scans to complete (timeout: 30m)..."
	for i in $(seq 1 90); do
		ALL_DONE=true
		for suite in $(oc get compliancesuite -n "$DEFAULT_COMPLIANCE_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
			PHASE=$(oc get compliancesuite "$suite" -n "$DEFAULT_COMPLIANCE_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
			if [[ "$PHASE" != "DONE" ]]; then
				ALL_DONE=false
				break
			fi
		done
		if [[ "$ALL_DONE" == "true" ]]; then
			log_success "$label scans completed."
			return 0
		fi
		echo -n "."
		sleep 20
	done
	echo ""
	log_error "$label scans did not complete within 30 minutes"
	oc get compliancesuite -n "$DEFAULT_COMPLIANCE_NAMESPACE"
	return 1
}

export_results() {
	local output_file="$1"
	oc get compliancecheckresult -n "$DEFAULT_COMPLIANCE_NAMESPACE" -o json >"$output_file"
	jq -r '{total: (.items | length), pass: ([.items[] | select(.status == "PASS")] | length), fail: ([.items[] | select(.status == "FAIL")] | length), manual: ([.items[] | select(.status == "MANUAL")] | length)} | "  Total: \(.total) | PASS: \(.pass) | FAIL: \(.fail) | MANUAL: \(.manual)"' "$output_file"
}

GROUP_LIST=$(build_group_list)
GROUP_COUNT=$(echo "$GROUP_LIST" | wc -l | tr -d ' ')
log_info "Groups to process: $GROUP_COUNT"

log_info "Phase 1: Baseline scan export"
if [[ "$SKIP_BASELINE" == "true" && -f "$OUTPUT_DIR/before-results.json" ]]; then
	log_info "Skipping baseline (using existing $OUTPUT_DIR/before-results.json)"
else
	log_info "Exporting baseline scan results..."
	export_results "$OUTPUT_DIR/before-results.json"
fi

log_info "Phase 2: Fetch and apply remediation MachineConfigs"
APPLIED_TOTAL=0
SKIPPED_GROUPS=0
APPLIED_GROUPS=0

while IFS= read -r group_id; do
	[[ -z "$group_id" ]] && continue

	compare=$(jq -r --arg g "$group_id" '.groups[$g].compare // empty' "$TRACKING")
	title=$(jq -r --arg g "$group_id" '.groups[$g].title // empty' "$TRACKING")

	if [[ -z "$compare" ]]; then
		log_warn "$group_id ($title): no compare branch, skipping"
		SKIPPED_GROUPS=$((SKIPPED_GROUPS + 1))
		continue
	fi

	log_info "$group_id ($title): fetching from $compare"
	mc_files=$(fetch_group_mcs "$group_id" "$compare" || true)

	if [[ -z "$mc_files" ]]; then
		log_warn "$group_id: no MC files found in branch $compare"
		SKIPPED_GROUPS=$((SKIPPED_GROUPS + 1))
		continue
	fi

	if [[ "$SKIP_APPLY" == "true" ]]; then
		APPLIED_GROUPS=$((APPLIED_GROUPS + 1))
		continue
	fi

	mc_dir="$OUTPUT_DIR/machineconfigs/$group_id"
	for mc_path in "$mc_dir"/*.yaml; do
		[[ ! -f "$mc_path" ]] && continue
		kind=$(yq e '.kind' "$mc_path" 2>/dev/null || echo "")
		if [[ "$kind" == "MachineConfig" || "$kind" == "APIServer" || "$kind" == "OAuth" ]]; then
			if [[ "$DRY_RUN" == "true" ]]; then
				log_info "  [DRY-RUN] Would apply: $(basename "$mc_path") ($kind)"
			else
				log_info "  Applying: $(basename "$mc_path") ($kind)"
				oc apply -f "$mc_path"
			fi
			APPLIED_TOTAL=$((APPLIED_TOTAL + 1))
		fi
	done
	APPLIED_GROUPS=$((APPLIED_GROUPS + 1))
done <<<"$GROUP_LIST"

log_info "Applied $APPLIED_TOTAL files from $APPLIED_GROUPS groups ($SKIPPED_GROUPS skipped)"

if [[ "$DRY_RUN" == "true" ]]; then
	log_info "[DRY-RUN] Skipping MCP rollout and re-scan"
	log_success "Dry run complete. MachineConfigs saved to $OUTPUT_DIR/machineconfigs/"
	exit 0
fi

if [[ "$SKIP_APPLY" != "true" && "$APPLIED_TOTAL" -gt 0 ]]; then
	log_info "Phase 3: Waiting for MCP rollout"
	for pool in $(oc get mcp -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
		log_info "  Waiting for MCP/$pool (timeout: 45m)..."
		if ! oc wait mcp/"$pool" --for=condition=Updated=True --timeout=45m; then
			log_warn "  MCP/$pool did not reach Updated=True within 45m"
		fi
	done
	oc get mcp -o wide
fi

log_info "Phase 4: Re-scan"
"$SCRIPT_DIR/utilities/restart-scans.sh" --all
wait_for_scans "post-remediation"

log_info "Phase 5: Export post-remediation results"
export_results "$OUTPUT_DIR/after-results.json"

log_info "Phase 6: Generate diff report"
python3 - "$OUTPUT_DIR" <<'PYSCRIPT'
import json, sys

output_dir = sys.argv[1]

with open(f"{output_dir}/before-results.json") as f:
    before = {item["metadata"]["name"]: item.get("status", "UNKNOWN") for item in json.load(f)["items"]}
with open(f"{output_dir}/after-results.json") as f:
    after = {item["metadata"]["name"]: item.get("status", "UNKNOWN") for item in json.load(f)["items"]}

flipped_pass, flipped_fail, unchanged_fail = [], [], []
for name in sorted(set(before) | set(after)):
    b, a = before.get(name, "MISSING"), after.get(name, "MISSING")
    if a == "PASS" and b == "FAIL":
        flipped_pass.append(name)
    elif a == "FAIL" and b == "PASS":
        flipped_fail.append(name)
    elif a == "FAIL" and b == "FAIL":
        unchanged_fail.append(name)

before_pass = sum(1 for v in before.values() if v == "PASS")
before_fail = sum(1 for v in before.values() if v == "FAIL")
after_pass = sum(1 for v in after.values() if v == "PASS")
after_fail = sum(1 for v in after.values() if v == "FAIL")

report = {
    "before_pass": before_pass, "before_fail": before_fail,
    "after_pass": after_pass, "after_fail": after_fail,
    "flipped_to_pass": flipped_pass,
    "flipped_to_fail": flipped_fail,
    "unchanged_fail": unchanged_fail,
}
with open(f"{output_dir}/diff-report.json", "w") as f:
    json.dump(report, f, indent=2)

print(f"\n{'='*60}")
print(f"  FULL REMEDIATION VERIFICATION REPORT")
print(f"{'='*60}")
print(f"  Before: {before_pass} PASS / {before_fail} FAIL")
print(f"  After:  {after_pass} PASS / {after_fail} FAIL")
print(f"  Flipped FAIL->PASS: {len(flipped_pass)}")
print(f"  Flipped PASS->FAIL: {len(flipped_fail)}")
print(f"  Unchanged FAIL:     {len(unchanged_fail)}")
print(f"{'='*60}")

if flipped_pass:
    print(f"\n  Checks fixed ({len(flipped_pass)}):")
    for n in flipped_pass[:20]:
        print(f"    + {n}")
    if len(flipped_pass) > 20:
        print(f"    ... and {len(flipped_pass) - 20} more")

if flipped_fail:
    print(f"\n  REGRESSIONS ({len(flipped_fail)}):")
    for n in flipped_fail:
        print(f"    ! {n}")

print()
PYSCRIPT

log_success "Full report saved to $OUTPUT_DIR/"
log_info "Files: before-results.json, after-results.json, diff-report.json"
