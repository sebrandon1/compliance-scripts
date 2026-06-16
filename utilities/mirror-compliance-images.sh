#!/bin/bash
# mirror-compliance-images.sh - Mirror compliance operator release images to quay.io
#
# Mirrors or builds compliance-operator, openscap-ocp, bundle, and catalog images
# for a specific release tag. Tries to mirror from upstream (ghcr.io) first,
# falls back to building from source when upstream images are unavailable.
#
# Usage:
#   ./utilities/mirror-compliance-images.sh [version]
#
# Arguments:
#   version    Release tag to mirror (default: auto-detect latest)
#
# Environment:
#   FORCE=true              Rebuild even if images already exist
#   MIRROR_REGISTRY=...     Target registry (default: quay.io/bapalm)
#   UPSTREAM_REGISTRY=...   Source registry (default: ghcr.io/complianceascode)
#
# Requires: skopeo, jq
# Optional: docker (with buildx) or podman — needed only when building from source

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

MIRROR_REGISTRY="${MIRROR_REGISTRY:-quay.io/bapalm}"
UPSTREAM_REGISTRY="${UPSTREAM_REGISTRY:-ghcr.io/complianceascode}"
FORCE="${FORCE:-false}"
CO_REF="${1:-}"

# Image names (order matters: bundle must come before catalog)
IMAGES=(compliance-operator openscap-ocp compliance-operator-bundle compliance-operator-catalog)

# Dockerfiles for building from source (relative to compliance-operator repo root)
# catalog is handled specially and has no single Dockerfile
get_dockerfile() {
	case "$1" in
	compliance-operator) echo "build/Dockerfile" ;;
	openscap-ocp) echo "images/openscap/Dockerfile" ;;
	compliance-operator-bundle) echo "bundle.Dockerfile" ;;
	*) echo "" ;;
	esac
}

usage() {
	cat <<USAGE
Usage: $(basename "$0") [version]

Mirror compliance operator release images to ${MIRROR_REGISTRY}.

Arguments:
  version    Release tag to mirror (e.g., v1.8.2). Auto-detects latest if omitted.

Environment:
  FORCE=true              Rebuild even if images already exist on target
  MIRROR_REGISTRY=...     Target registry (default: ${MIRROR_REGISTRY})
  UPSTREAM_REGISTRY=...   Source registry (default: ${UPSTREAM_REGISTRY})
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

require_cmd skopeo jq

# ── Detect version ──

if [[ -z "$CO_REF" ]]; then
	log_info "Auto-detecting latest compliance-operator release..."
	CO_REF=$(curl -fsSL https://api.github.com/repos/ComplianceAsCode/compliance-operator/releases/latest |
		jq -r '.tag_name')
	if [[ -z "$CO_REF" || "$CO_REF" == "null" ]]; then
		log_error "Could not detect latest release"
		exit 1
	fi
fi
log_info "Target version: $CO_REF"

# ── Detect what exists ──

log_info "Checking image availability..."

# Track per-image state with simple variables
NEEDS_WORK=false
ANY_BUILD_NEEDED=false

# Arrays to track which images need work
IMAGES_TO_MIRROR=()
IMAGES_TO_BUILD=()
IMAGES_SKIPPED=()

for IMG in "${IMAGES[@]}"; do
	TARGET="${MIRROR_REGISTRY}/${IMG}:${CO_REF}"
	UPSTREAM="${UPSTREAM_REGISTRY}/${IMG}:${CO_REF}"
	TARGET_HAS=false
	UPSTREAM_HAS=false

	if skopeo inspect --raw --no-creds "docker://${TARGET}" &>/dev/null; then
		TARGET_HAS=true
	fi
	if skopeo inspect --raw --no-creds "docker://${UPSTREAM}" &>/dev/null; then
		UPSTREAM_HAS=true
	fi

	log_debug "  $IMG -> target:${TARGET_HAS} upstream:${UPSTREAM_HAS}"

	if [[ "$FORCE" != "true" && "$TARGET_HAS" == "true" ]]; then
		IMAGES_SKIPPED+=("$IMG")
		continue
	fi

	NEEDS_WORK=true
	if [[ "$UPSTREAM_HAS" == "true" ]]; then
		IMAGES_TO_MIRROR+=("$IMG")
	else
		IMAGES_TO_BUILD+=("$IMG")
		ANY_BUILD_NEEDED=true
	fi
done

if [[ "$NEEDS_WORK" == "false" ]]; then
	log_success "All images already exist at ${MIRROR_REGISTRY} for $CO_REF"
	log_info "Set FORCE=true to rebuild"
	exit 0
fi

# ── Clone source if any builds are needed ──

WORK_DIR=""
if [[ "$ANY_BUILD_NEEDED" == "true" ]]; then
	WORK_DIR=$(make_temp_dir)
	log_info "Cloning compliance-operator source (ref: $CO_REF)..."
	git clone --depth 1 --branch "$CO_REF" \
		https://github.com/ComplianceAsCode/compliance-operator.git "$WORK_DIR/co-src"
fi

# ── Helper functions ──

build_and_push() {
	local context="$1"
	local dockerfile="$2"
	local tag="$3"

	if command -v docker &>/dev/null && docker buildx version 2>&1 | grep -q "github.com/docker"; then
		docker buildx build \
			-f "${context}/${dockerfile}" \
			--platform linux/amd64,linux/arm64 \
			--tag "$tag" \
			--push \
			"$context"
	elif command -v podman &>/dev/null; then
		log_warn "Using podman (single arch only)"
		podman build \
			-f "${context}/${dockerfile}" \
			--tag "$tag" \
			"$context"
		podman push "$tag"
	else
		log_error "Neither docker (with buildx) nor podman found"
		return 1
	fi
}

build_catalog() {
	local target="${MIRROR_REGISTRY}/compliance-operator-catalog:${CO_REF}"
	local bundle_tag="${MIRROR_REGISTRY}/compliance-operator-bundle:${CO_REF}"

	if ! command -v opm &>/dev/null; then
		local opm_version
		opm_version=$(grep -oP 'OPM_VERSION\?\=\K[0-9.]+' "$WORK_DIR/co-src/Makefile" 2>/dev/null || echo "1.39.0")
		log_info "    Installing opm v${opm_version}..."
		local arch
		arch=$(uname -m)
		case "$arch" in
		x86_64) arch="amd64" ;;
		aarch64) arch="arm64" ;;
		esac
		local os
		os=$(uname -s | tr '[:upper:]' '[:lower:]')
		curl -sSLo /tmp/opm \
			"https://github.com/operator-framework/operator-registry/releases/download/v${opm_version}/${os}-${arch}-opm"
		chmod +x /tmp/opm
		OPM=/tmp/opm
	else
		OPM=opm
	fi

	mkdir -p "$WORK_DIR/catalog-build/catalog"
	cp "$WORK_DIR/co-src/catalog/preamble.json" "$WORK_DIR/catalog-build/catalog/compliance-operator-catalog.json"
	$OPM render "$bundle_tag" >>"$WORK_DIR/catalog-build/catalog/compliance-operator-catalog.json"

	cat >"$WORK_DIR/catalog-build/Dockerfile" <<'DEOF'
FROM quay.io/operator-framework/opm:latest as builder
COPY catalog /configs
RUN ["/bin/opm", "serve", "/configs", "--cache-dir=/tmp/cache", "--cache-only"]

FROM quay.io/operator-framework/opm:latest
ENTRYPOINT ["/bin/opm"]
CMD ["serve", "/configs", "--cache-dir=/tmp/cache"]
COPY --from=builder /configs /configs
COPY --from=builder /tmp/cache /tmp/cache
LABEL operators.operatorframework.io.index.configs.v1=/configs
DEOF

	build_and_push "$WORK_DIR/catalog-build" "Dockerfile" "$target"
}

# ── Mirror images from upstream ──

if [[ ${#IMAGES_TO_MIRROR[@]} -gt 0 ]]; then
	for IMG in "${IMAGES_TO_MIRROR[@]}"; do
		UPSTREAM="${UPSTREAM_REGISTRY}/${IMG}:${CO_REF}"
		TARGET="${MIRROR_REGISTRY}/${IMG}:${CO_REF}"
		log_info "  $IMG: mirroring from upstream..."
		skopeo copy --all "docker://${UPSTREAM}" "docker://${TARGET}"
	done
fi

# ── Build images from source ──

if [[ ${#IMAGES_TO_BUILD[@]} -gt 0 ]]; then
	for IMG in "${IMAGES_TO_BUILD[@]}"; do
		TARGET="${MIRROR_REGISTRY}/${IMG}:${CO_REF}"
		log_info "  $IMG: building from source..."

		if [[ "$IMG" == "compliance-operator-catalog" ]]; then
			build_catalog
		else
			DOCKERFILE=$(get_dockerfile "$IMG")
			if [[ -z "$DOCKERFILE" ]]; then
				log_error "  $IMG: no Dockerfile configured"
				continue
			fi
			build_and_push "$WORK_DIR/co-src" "$DOCKERFILE" "$TARGET"
		fi
	done
fi

# ── Verify ──

log_info "Verifying architectures..."
VERIFY_ARGS=()
for IMG in "${IMAGES[@]}"; do
	VERIFY_ARGS+=("${MIRROR_REGISTRY}/${IMG}:${CO_REF}")
done

"$SCRIPT_DIR/utilities/verify-mirror-architectures.sh" "${VERIFY_ARGS[@]}"

# ── Summary ──

echo ""
log_success "Mirror complete for $CO_REF"
print_summary \
	"Version" "$CO_REF" \
	"Registry" "$MIRROR_REGISTRY" \
	"Mirrored" "${#IMAGES_TO_MIRROR[@]}" \
	"Built" "${#IMAGES_TO_BUILD[@]}" \
	"Skipped" "${#IMAGES_SKIPPED[@]}"

echo ""
echo "To deploy this version:"
echo "  oc set env deployment/compliance-operator -n openshift-compliance \\"
echo "    RELATED_IMAGE_OPERATOR=${MIRROR_REGISTRY}/compliance-operator:${CO_REF} \\"
echo "    RELATED_IMAGE_OPENSCAP=${MIRROR_REGISTRY}/openscap-ocp:${CO_REF} \\"
echo "    RELATED_IMAGE_PROFILE=${MIRROR_REGISTRY}/k8scontent:latest"
