#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

OCP_VERSION="${1:-}"
CONTENT_IMAGE="${CONTENT_IMAGE:-quay.io/bapalm/k8scontent}"
CONTENT_TAG="${CONTENT_TAG:-v0.1.80}"
OPENSCAP_IMAGE="${OPENSCAP_IMAGE:-quay.io/bapalm/openscap-ocp}"
OPENSCAP_TAG="${OPENSCAP_TAG:-234bdd200637}"
MUST_GATHER_IMAGE="${MUST_GATHER_IMAGE:-quay.io/bapalm/must-gather-ocp}"
MUST_GATHER_TAG="${MUST_GATHER_TAG:-234bdd200637}"
PULL_SECRET="${PULL_SECRET:-$HOME/Downloads/pull-secret.txt}"
PROFILES="${PROFILES:-xccdf_org.ssgproject.content_profile_e8,xccdf_org.ssgproject.content_profile_moderate}"
RESULTS_DIR="${RESULTS_DIR:-/tmp/rhcos-scan-results}"
SUMMARY_FILE="${SUMMARY_FILE:-}"

usage() {
	cat <<USAGE
Usage: $(basename "$0") <ocp-version>

Run offline OSCAP compliance scan against an extracted RHCOS rootfs.

Arguments:
  ocp-version    OCP release version (e.g., 4.21 or 4.21.8)
                 Minor versions (4.21) auto-resolve to latest z-stream.

Environment:
  CONTENT_IMAGE     Content image repo (default: quay.io/bapalm/k8scontent)
  CONTENT_TAG       Content image tag (default: v0.1.80)
  OPENSCAP_IMAGE    Scanner image repo (default: quay.io/bapalm/openscap-ocp)
  OPENSCAP_TAG      Scanner image tag (default: 234bdd200637)
  MUST_GATHER_IMAGE Must-gather image repo (default: quay.io/bapalm/must-gather-ocp)
  MUST_GATHER_TAG   Must-gather image tag (default: 234bdd200637)
  PULL_SECRET       Path to OCP pull secret (default: ~/Downloads/pull-secret.txt)
  PROFILES          Comma-separated SCAP profiles (default: e8,moderate)
  RESULTS_DIR       Output directory (default: /tmp/rhcos-scan-results)
  SUMMARY_FILE      Write markdown summary to this file (optional, used by CI)

Example:
  $(basename "$0") 4.21
  CONTENT_TAG=v0.1.79 $(basename "$0") 4.18.12
USAGE
}

if [[ -z "$OCP_VERSION" || "$OCP_VERSION" == "-h" || "$OCP_VERSION" == "--help" ]]; then
	usage
	exit 0
fi

if [[ ! -f "$PULL_SECRET" ]]; then
	log_error "Pull secret not found at $PULL_SECRET"
	log_info "Set PULL_SECRET=/path/to/pull-secret.txt"
	exit 1
fi

# Resolve minor version to latest z-stream (try stable, then candidate)
if [[ "$OCP_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
	for CHANNEL in "stable-${OCP_VERSION}" "candidate-${OCP_VERSION}"; do
		RESOLVED=$(curl -sSL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${CHANNEL}/release.txt" 2>/dev/null |
			grep "^Name:" | awk '{print $2}' || echo "")
		if [[ -n "$RESOLVED" ]]; then
			log_info "Resolved ${OCP_VERSION} via ${CHANNEL}: ${RESOLVED}"
			OCP_VERSION="$RESOLVED"
			break
		fi
	done
	if [[ "$OCP_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
		log_error "Could not resolve ${OCP_VERSION} to a z-stream release"
		exit 1
	fi
fi

SCANNER="${OPENSCAP_IMAGE}:${OPENSCAP_TAG}"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"; podman rm -f rhcos-scan-extract content-scan-extract 2>/dev/null || true' EXIT

RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:${OCP_VERSION}-x86_64"

log_info "Extracting RHCOS image from $RELEASE_IMAGE..."
RHCOS_IMAGE=$(oc adm release info --registry-config "$PULL_SECRET" "$RELEASE_IMAGE" --image-for=rhel-coreos 2>/dev/null)
if [[ -z "$RHCOS_IMAGE" ]]; then
	log_error "Could not extract RHCOS image reference"
	exit 1
fi
log_info "RHCOS image: $RHCOS_IMAGE"

log_info "Pulling RHCOS image..."
podman pull --authfile "$PULL_SECRET" --platform linux/amd64 "$RHCOS_IMAGE" 2>&1 | tail -1

log_info "Extracting rootfs..."
podman create --name rhcos-scan-extract "$RHCOS_IMAGE" 2>/dev/null
ROOTFS="$WORK_DIR/rhcos-root"
mkdir -p "$ROOTFS"
podman export rhcos-scan-extract | tar -C "$ROOTFS" -xf - || true

RHCOS_VERSION="unknown"
for osrel in "$ROOTFS/usr/lib/os-release" "$ROOTFS/etc/os-release"; do
	if [[ -e "$osrel" ]]; then
		VER=$(grep "^VERSION=" "$osrel" 2>/dev/null | cut -d= -f2 | tr -d '"')
		if [[ -n "$VER" ]]; then
			RHCOS_VERSION="$VER"
			break
		fi
	fi
done

if [[ "$RHCOS_VERSION" == "unknown" ]]; then
	log_warn "Could not determine RHCOS version from rootfs"
fi
log_info "RHCOS version: $RHCOS_VERSION"

log_info "Key config files:"
ls -la "$ROOTFS/etc/ssh/sshd_config" 2>/dev/null || echo "  sshd_config: not found"
ls -la "$ROOTFS/etc/ssh/sshd_config.d/" 2>/dev/null || echo "  sshd_config.d/: not found"
ls -d "$ROOTFS/etc/sysctl.d/" 2>/dev/null || echo "  sysctl.d/: not found"
ls -d "$ROOTFS/etc/audit/" 2>/dev/null || echo "  audit/: not found"

log_info "Extracting SCAP content from ${CONTENT_IMAGE}:${CONTENT_TAG}..."
podman create --name content-scan-extract "${CONTENT_IMAGE}:${CONTENT_TAG}" 2>/dev/null
podman cp content-scan-extract:/ssg-rhcos4-ds.xml "$WORK_DIR/ssg-rhcos4-ds.xml"
podman rm content-scan-extract 2>/dev/null

mkdir -p "$RESULTS_DIR"

IFS=',' read -ra PROFILE_LIST <<<"$PROFILES"
for PROFILE in "${PROFILE_LIST[@]}"; do
	PROFILE_SHORT="${PROFILE##*_profile_}"
	log_info "Scanning profile: ${PROFILE_SHORT}..."

	podman run --rm \
		-v "$ROOTFS:/hostroot:ro" \
		-v "$WORK_DIR/ssg-rhcos4-ds.xml:/content/ssg-rhcos4-ds.xml:ro" \
		-v "$RESULTS_DIR:/results:z" \
		-e OSCAP_PROBE_ROOT=/hostroot \
		"$SCANNER" \
		oscap xccdf eval \
		--profile "$PROFILE" \
		--results "/results/results-${PROFILE_SHORT}.xml" \
		/content/ssg-rhcos4-ds.xml \
		|| true

	RESULTS_FILE="$RESULTS_DIR/results-${PROFILE_SHORT}.xml"
	ACTUAL_FAILS="$RESULTS_DIR/actual-${PROFILE_SHORT}-fails.txt"
	MARKDOWN_OUT="$RESULTS_DIR/summary-${PROFILE_SHORT}.md"
	if [[ -f "$RESULTS_FILE" ]]; then
		log_info "Results for ${PROFILE_SHORT}:"
		python3 "$SCRIPT_DIR/scripts/parse-oscap-results.py" "$RESULTS_FILE" \
			--tracking "$SCRIPT_DIR/docs/_data/tracking.json" \
			--format text \
			--failing-file "$ACTUAL_FAILS" \
			--markdown-file "$MARKDOWN_OUT"
	else
		log_warn "No results file for ${PROFILE_SHORT}"
	fi
done

echo ""
log_success "Scan complete. Results in $RESULTS_DIR"
log_info "OCP: $OCP_VERSION | RHCOS: $RHCOS_VERSION | Content: ${CONTENT_TAG} | Scanner: ${OPENSCAP_TAG}"

# Generate markdown summary if SUMMARY_FILE is set (used by CI)
if [[ -n "$SUMMARY_FILE" ]]; then
	{
		echo "## RHCOS Static Compliance Scan"
		echo ""
		echo "| Field | Value |"
		echo "|-------|-------|"
		echo "| OCP Release | \`${OCP_VERSION}\` |"
		echo "| RHCOS Version | \`${RHCOS_VERSION}\` |"
		echo "| Content Image | \`${CONTENT_IMAGE}:${CONTENT_TAG}\` |"
		echo "| Scanner Image | \`${SCANNER}\` |"
		echo "| Must-Gather | \`${MUST_GATHER_IMAGE}:${MUST_GATHER_TAG}\` |"
		echo ""

		for PROFILE in "${PROFILE_LIST[@]}"; do
			PROFILE_SHORT="${PROFILE##*_profile_}"
			MARKDOWN_OUT="$RESULTS_DIR/summary-${PROFILE_SHORT}.md"
			ACTUAL_FAILS="$RESULTS_DIR/actual-${PROFILE_SHORT}-fails.txt"

			if [[ -f "$MARKDOWN_OUT" ]]; then
				echo "### Profile: ${PROFILE_SHORT}"
				echo ""
				cat "$MARKDOWN_OUT"
				echo ""

				# Extract major.minor from version (e.g., 4.22.0-rc.0 -> 4.22)
				OCP_MINOR=$(echo "$OCP_VERSION" | grep -oE '^[0-9]+\.[0-9]+')
				BASELINE_DIR="$SCRIPT_DIR/tests/rhcos-baselines"
				BASELINE="$BASELINE_DIR/rhcos-${OCP_MINOR}-${PROFILE_SHORT}-expected-fails.txt"

				DIFF_JSON="$RESULTS_DIR/baseline-diff-${PROFILE_SHORT}.json"

				echo "### Baseline Comparison (${PROFILE_SHORT}, OCP ${OCP_MINOR})"
				echo ""
				if [[ -f "$BASELINE" ]]; then
					NEW_FAILS=$(comm -13 <(sort "$BASELINE") "$ACTUAL_FAILS")
					FIXED=$(comm -23 <(sort "$BASELINE") "$ACTUAL_FAILS")
					HAS_CHANGES=false

					if [[ -z "$NEW_FAILS" && -z "$FIXED" ]]; then
						echo "No changes from baseline."
					else
						HAS_CHANGES=true
						if [[ -n "$NEW_FAILS" ]]; then
							echo "**New FAILs (not in baseline):**"
							echo ""
							echo '```'
							echo "$NEW_FAILS"
							echo '```'
							echo ""
						fi
						if [[ -n "$FIXED" ]]; then
							echo "**Fixed (in baseline but now PASS):**"
							echo ""
							echo '```'
							echo "$FIXED"
							echo '```'
							echo ""
						fi
					fi

					# Write structured diff for workflow consumption
					python3 -c "
import json, sys
new_fails = [x for x in '''${NEW_FAILS}'''.strip().split('\n') if x]
fixed = [x for x in '''${FIXED}'''.strip().split('\n') if x]
json.dump({
    'ocp_version': '${OCP_VERSION}',
    'ocp_minor': '${OCP_MINOR}',
    'rhcos_version': '${RHCOS_VERSION}',
    'profile': '${PROFILE_SHORT}',
    'new_fails': new_fails,
    'fixed': fixed,
    'has_changes': len(new_fails) > 0 or len(fixed) > 0
}, open('${DIFF_JSON}', 'w'), indent=2)
"
				else
					echo "No baseline exists yet. Saving current results as baseline."
					echo ""
					mkdir -p "$BASELINE_DIR"
					cp "$ACTUAL_FAILS" "$BASELINE"
					FAIL_COUNT=$(wc -l < "$ACTUAL_FAILS" | xargs)
					echo "Saved ${FAIL_COUNT} expected FAILs to \`tests/rhcos-baselines/rhcos-${OCP_MINOR}-${PROFILE_SHORT}-expected-fails.txt\`"
					echo ""

					# No changes on first run
					python3 -c "
import json
json.dump({
    'ocp_version': '${OCP_VERSION}',
    'ocp_minor': '${OCP_MINOR}',
    'rhcos_version': '${RHCOS_VERSION}',
    'profile': '${PROFILE_SHORT}',
    'new_fails': [],
    'fixed': [],
    'has_changes': False,
    'baseline_created': True
}, open('${DIFF_JSON}', 'w'), indent=2)
"
				fi
			fi
		done
	} >>"$SUMMARY_FILE"
	log_info "Summary written to $SUMMARY_FILE"
fi
