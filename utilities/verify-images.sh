#!/bin/bash
# verify-images.sh - Verify that required container images are accessible
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Timeout for image checks (seconds)
TIMEOUT="${TIMEOUT:-30}"

# Determine timeout command (macOS uses gtimeout from coreutils, Linux uses timeout)
if command -v timeout &>/dev/null; then
	TIMEOUT_CMD="timeout"
elif command -v gtimeout &>/dev/null; then
	TIMEOUT_CMD="gtimeout"
else
	# Fallback: no timeout command available, just run the command directly
	TIMEOUT_CMD=""
fi

# Helper function to run commands with optional timeout
run_with_timeout() {
	if [[ -n "$TIMEOUT_CMD" ]]; then
		$TIMEOUT_CMD "$TIMEOUT" "$@"
	else
		"$@"
	fi
}

# Images to verify
COMPLIANCE_OPERATOR_IMAGES=(
	"ghcr.io/complianceascode/compliance-operator:latest"
	"ghcr.io/complianceascode/k8scontent:latest"
	"ghcr.io/complianceascode/compliance-operator-catalog:latest"
)

MIRROR_IMAGES=(
	"quay.io/bapalm/compliance-operator:v1.7.0"
	"quay.io/bapalm/k8scontent:v1.7.0"
	"quay.io/bapalm/compliance-operator-catalog:v1.7.0"
	"quay.io/bapalm/compliance-operator:v1.8.2"
	"quay.io/bapalm/k8scontent:v1.8.2"
	"quay.io/bapalm/compliance-operator-catalog:v1.8.2"
)

OPENSHIFT_MARKETPLACE_IMAGES=(
	"registry.redhat.io/redhat/community-operator-index:v4.17"
	"registry.redhat.io/redhat/community-operator-index:v4.18"
	"registry.redhat.io/redhat/community-operator-index:v4.19"
	"registry.redhat.io/redhat/community-operator-index:v4.20"
)

usage() {
	cat <<USAGE
Usage: $(basename "$0") [options]

Verify that required container images are accessible before deployment.

Options:
  --all              Check all images (compliance operator + marketplace + mirrors)
  --compliance       Check only compliance operator images (default)
  --marketplace      Check only OpenShift marketplace images
  --mirrors          Check only quay.io/bapalm mirror images
  --registry <url>   Test connectivity to a specific registry
  --image <image>    Test a specific image
  --timeout <secs>   Timeout for each check (default: 30)
  -h, --help         Show this help

Examples:
  $(basename "$0")                              # Check compliance operator images
  $(basename "$0") --all                        # Check all images
  $(basename "$0") --image quay.io/myorg/myimg  # Check specific image
  $(basename "$0") --registry registry.redhat.io  # Test registry connectivity
USAGE
}

# Parse arguments
CHECK_COMPLIANCE=true
CHECK_MARKETPLACE=false
CHECK_MIRRORS=false
SPECIFIC_IMAGE=""
SPECIFIC_REGISTRY=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--all)
		CHECK_COMPLIANCE=true
		CHECK_MARKETPLACE=true
		CHECK_MIRRORS=true
		shift
		;;
	--compliance)
		CHECK_COMPLIANCE=true
		CHECK_MARKETPLACE=false
		shift
		;;
	--marketplace)
		CHECK_COMPLIANCE=false
		CHECK_MARKETPLACE=true
		shift
		;;
	--mirrors)
		CHECK_COMPLIANCE=false
		CHECK_MARKETPLACE=false
		CHECK_MIRRORS=true
		shift
		;;
	--registry)
		SPECIFIC_REGISTRY="$2"
		shift 2
		;;
	--image)
		SPECIFIC_IMAGE="$2"
		shift 2
		;;
	--timeout)
		TIMEOUT="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown option: $1"
		usage
		exit 1
		;;
	esac
done

# Check if we have the tools we need
check_tools() {
	require_cmd curl

	if command -v podman &>/dev/null; then
		CONTAINER_CMD="podman"
	elif command -v docker &>/dev/null; then
		CONTAINER_CMD="docker"
	elif command -v oc &>/dev/null; then
		CONTAINER_CMD="oc-debug"
	else
		log_error "Missing required tools: podman or docker"
		exit 1
	fi
}

# Test registry connectivity
test_registry() {
	local registry="$1"
	local proto="${2:-https}"

	echo -n "  Testing $registry... "

	# Extract just the hostname if a full image ref was passed
	local host="${registry%%/*}"

	if run_with_timeout curl -sSf -o /dev/null "${proto}://${host}/v2/" 2>/dev/null; then
		echo -e "${GREEN}✅ reachable${NC}"
		return 0
	elif run_with_timeout curl -sSf -o /dev/null -w "%{http_code}" "${proto}://${host}/v2/" 2>/dev/null | grep -qE "^(401|403)$"; then
		# 401/403 means registry is reachable but requires auth
		echo -e "${GREEN}✅ reachable (auth required)${NC}"
		return 0
	else
		echo -e "${RED}❌ unreachable${NC}"
		return 1
	fi
}

# Test if an image manifest exists (without pulling the full image)
test_image_manifest() {
	local image="$1"

	echo -n "  Checking $image... "

	# Use skopeo if available (fastest, doesn't pull)
	if command -v skopeo &>/dev/null; then
		# Use --raw to get the manifest list without architecture filtering
		# This avoids "no image found for architecture" errors on Apple Silicon
		if run_with_timeout skopeo inspect --raw --no-creds "docker://$image" &>/dev/null 2>&1; then
			echo -e "${GREEN}✅ available${NC}"
			return 0
		elif run_with_timeout skopeo inspect --raw "docker://$image" &>/dev/null 2>&1; then
			echo -e "${GREEN}✅ available (with auth)${NC}"
			return 0
		fi
		# Try with amd64 override (for ARM64 macs checking x86 images)
		if run_with_timeout skopeo inspect --override-arch amd64 --no-creds "docker://$image" &>/dev/null 2>&1; then
			echo -e "${GREEN}✅ available (amd64)${NC}"
			return 0
		fi
	fi

	# Fallback: try to pull with container runtime (more reliable but slower)
	if [[ "$CONTAINER_CMD" == "oc-debug" ]]; then
		# Use oc image info if available
		if oc image info "$image" &>/dev/null 2>&1; then
			echo -e "${GREEN}✅ available${NC}"
			return 0
		fi
	else
		# Try pulling just the manifest
		if run_with_timeout $CONTAINER_CMD manifest inspect "$image" &>/dev/null 2>&1; then
			echo -e "${GREEN}✅ available${NC}"
			return 0
		fi

		# Last resort: try a pull (will be slow)
		if run_with_timeout $CONTAINER_CMD pull --quiet "$image" &>/dev/null 2>&1; then
			echo -e "${GREEN}✅ available (pulled)${NC}"
			return 0
		fi
	fi

	echo -e "${RED}❌ not available${NC}"
	return 1
}

# Main
echo "════════════════════════════════════════════════════════════════════"
echo "🔍 Container Image Verification"
echo "════════════════════════════════════════════════════════════════════"
echo ""

check_tools
log_info "Using container command: $CONTAINER_CMD"
if [[ -n "$TIMEOUT_CMD" ]]; then
	log_info "Timeout command: $TIMEOUT_CMD (${TIMEOUT}s per check)"
else
	log_info "Timeout: not available (install coreutils for timeout support)"
fi
echo ""

FAILED=0
PASSED=0

# Test specific registry if requested
if [[ -n "$SPECIFIC_REGISTRY" ]]; then
	echo "Testing registry connectivity:"
	if test_registry "$SPECIFIC_REGISTRY"; then
		((PASSED++))
	else
		((FAILED++))
	fi
	echo ""
fi

# Test specific image if requested
if [[ -n "$SPECIFIC_IMAGE" ]]; then
	echo "Testing specific image:"
	if test_image_manifest "$SPECIFIC_IMAGE"; then
		((PASSED++))
	else
		((FAILED++))
	fi
	echo ""
fi

# Test compliance operator images
if [[ "$CHECK_COMPLIANCE" == "true" && -z "$SPECIFIC_IMAGE" && -z "$SPECIFIC_REGISTRY" ]]; then
	echo "Compliance Operator Images:"
	for image in "${COMPLIANCE_OPERATOR_IMAGES[@]}"; do
		if test_image_manifest "$image"; then
			((PASSED++))
		else
			((FAILED++))
		fi
	done
	echo ""
fi

# Test marketplace images
if [[ "$CHECK_MARKETPLACE" == "true" && -z "$SPECIFIC_IMAGE" && -z "$SPECIFIC_REGISTRY" ]]; then
	echo "OpenShift Marketplace Images:"
	echo -e "${YELLOW}[NOTE] These require Red Hat registry authentication${NC}"
	for image in "${OPENSHIFT_MARKETPLACE_IMAGES[@]}"; do
		if test_image_manifest "$image"; then
			((PASSED++))
		else
			((FAILED++))
		fi
	done
	echo ""
fi

# Test mirror images
if [[ "$CHECK_MIRRORS" == "true" && -z "$SPECIFIC_IMAGE" && -z "$SPECIFIC_REGISTRY" ]]; then
	echo "Mirror Images (quay.io/bapalm):"
	for image in "${MIRROR_IMAGES[@]}"; do
		if test_image_manifest "$image"; then
			((PASSED++))
		else
			((FAILED++))
		fi
	done
	echo ""
fi

# Summary
echo "════════════════════════════════════════════════════════════════════"
echo -e "Summary: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
echo "════════════════════════════════════════════════════════════════════"

if [[ $FAILED -gt 0 ]]; then
	echo ""
	echo -e "${YELLOW}Troubleshooting tips:${NC}"
	echo "  1. Check network connectivity to container registries"
	echo "  2. For registry.redhat.io, ensure you have a valid pull secret:"
	echo "     oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\\.dockerconfigjson}' | base64 -d"
	echo "  3. For CRC, try: crc config set network-mode user && crc stop && crc start"
	echo "  4. Verify DNS resolution: nslookup registry.redhat.io"
	echo ""
	exit 1
fi

echo ""
echo -e "${GREEN}All image checks passed!${NC}"
exit 0
