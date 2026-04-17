#!/bin/bash
# verify-mirror-architectures.sh - Verify mirrored images have both amd64 and arm64
#
# Checks that all compliance operator mirror images on quay.io/bapalm
# have manifests for both amd64 and arm64 architectures.
#
# Usage: ./utilities/verify-mirror-architectures.sh
#
# Requires: skopeo, jq

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Mirror images to verify (registry/image:tag)
# Only include images that are actually produced by the mirror workflow.
MIRROR_IMAGES=(
	"quay.io/bapalm/compliance-operator-catalog:v1.7.0"
	"quay.io/bapalm/compliance-operator-catalog:v1.8.2"
	"quay.io/bapalm/compliance-operator-bundle:v1.8.2"
)
REQUIRED_ARCHES=("amd64" "arm64")

require_cmd skopeo jq

echo "════════════════════════════════════════════════════════════════════"
echo "🔍 Mirror Image Architecture Verification"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Images: ${#MIRROR_IMAGES[@]}"
echo "Required: ${REQUIRED_ARCHES[*]}"
echo ""

FAILED=0
PASSED=0

for image in "${MIRROR_IMAGES[@]}"; do
	echo -n "  ${image} "

	# Get the manifest
	manifest=$(skopeo inspect --raw --no-creds "docker://${image}" 2>/dev/null) || {
		echo -e "${RED}✗ not found${NC}"
		FAILED=$((FAILED + 1))
		continue
	}

	# Check if it's a manifest list (multi-arch) or single manifest
	media_type=$(echo "$manifest" | jq -r '.mediaType // .schemaVersion' 2>/dev/null)

	if echo "$media_type" | grep -qE "manifest\.list|image\.index"; then
		# Multi-arch manifest list — extract architectures
		arches=$(echo "$manifest" | jq -r '[.manifests[].platform.architecture] | unique | sort | join(", ")' 2>/dev/null)
		missing=()
		for arch in "${REQUIRED_ARCHES[@]}"; do
			if ! echo "$manifest" | jq -e ".manifests[] | select(.platform.architecture == \"${arch}\")" &>/dev/null; then
				missing+=("$arch")
			fi
		done

		if [[ ${#missing[@]} -eq 0 ]]; then
			echo -e "${GREEN}✓ [${arches}]${NC}"
			PASSED=$((PASSED + 1))
		else
			echo -e "${RED}✗ missing: ${missing[*]} (has: ${arches})${NC}"
			FAILED=$((FAILED + 1))
		fi
	else
		# Single-arch manifest
		arch=$(echo "$manifest" | jq -r '.architecture // "unknown"' 2>/dev/null)
		echo -e "${RED}✗ single-arch only (${arch}), expected multi-arch${NC}"
		FAILED=$((FAILED + 1))
	fi
done
echo ""

# Summary
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
