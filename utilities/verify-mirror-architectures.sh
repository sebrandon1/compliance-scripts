#!/bin/bash
# verify-mirror-architectures.sh - Verify container images have required architectures
#
# Usage:
#   ./utilities/verify-mirror-architectures.sh image1:tag image2:tag ...
#   ./utilities/verify-mirror-architectures.sh   # (no args: checks all known mirror images)
#
# Requires: skopeo, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
	echo "Usage: $(basename "$0") [image:tag ...]"
	echo ""
	echo "Verify container images have required architectures (amd64, arm64)."
	echo "With no arguments, checks all known mirror images on quay.io/bapalm."
	exit 0
}

[[ "${1:-}" =~ ^(-h|--help)$ ]] && usage

REQUIRED_ARCHES=("amd64" "arm64")

require_cmd skopeo jq

# If arguments provided, use them; otherwise auto-discover from quay.io
if [[ $# -gt 0 ]]; then
	IMAGES=("$@")
else
	echo "No images specified, checking all known mirror images on quay.io/bapalm..."
	echo ""
	IMAGES=()
	for repo in compliance-operator openscap-ocp compliance-operator-bundle compliance-operator-catalog k8scontent; do
		tags=$(skopeo list-tags --no-creds "docker://quay.io/bapalm/${repo}" 2>/dev/null | jq -r '.Tags[]' 2>/dev/null | grep "^v" | grep -vE "-(amd64|arm64|ppc64le|s390x)$" || true)
		for tag in $tags; do
			IMAGES+=("quay.io/bapalm/${repo}:${tag}")
		done
	done
	if [[ ${#IMAGES[@]} -eq 0 ]]; then
		log_error "No versioned images found on quay.io/bapalm"
		exit 1
	fi
fi

echo "════════════════════════════════════════════════════════════════════"
echo "Mirror Image Architecture Verification"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Images: ${#IMAGES[@]}"
echo "Required: ${REQUIRED_ARCHES[*]}"
echo ""

FAILED=0
PASSED=0

for image in "${IMAGES[@]}"; do
	echo -n "  ${image} "

	manifest=$(skopeo inspect --raw --no-creds "docker://${image}" 2>/dev/null) || {
		echo -e "${RED}not found${NC}"
		FAILED=$((FAILED + 1))
		continue
	}

	media_type=$(echo "$manifest" | jq -r '.mediaType // .schemaVersion' 2>/dev/null)

	if echo "$media_type" | grep -qE "manifest\.list|image\.index"; then
		arches=$(echo "$manifest" | jq -r '[.manifests[].platform.architecture] | unique | sort | join(", ")' 2>/dev/null)
		missing=()
		for arch in "${REQUIRED_ARCHES[@]}"; do
			if ! echo "$manifest" | jq -e ".manifests[] | select(.platform.architecture == \"${arch}\")" &>/dev/null; then
				missing+=("$arch")
			fi
		done

		if [[ ${#missing[@]} -eq 0 ]]; then
			echo -e "${GREEN}OK [${arches}]${NC}"
			PASSED=$((PASSED + 1))
		else
			echo -e "${RED}missing: ${missing[*]} (has: ${arches})${NC}"
			FAILED=$((FAILED + 1))
		fi
	else
		arch=$(echo "$manifest" | jq -r '.architecture // "unknown"' 2>/dev/null)
		echo -e "${RED}single-arch only (${arch}), expected multi-arch${NC}"
		FAILED=$((FAILED + 1))
	fi
done
echo ""

echo "════════════════════════════════════════════════════════════════════"
echo -e "Summary: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}"
echo "════════════════════════════════════════════════════════════════════"

if [[ $FAILED -gt 0 ]]; then
	echo ""
	echo -e "${YELLOW}To fix missing architectures, re-run the mirror workflow:${NC}"
	echo "  gh workflow run mirror-compliance-images.yml -f force=true"
	echo ""
	exit 1
fi

echo ""
echo -e "${GREEN}All mirror images have both amd64 and arm64!${NC}"
exit 0
