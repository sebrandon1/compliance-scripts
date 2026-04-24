#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONTENT_REPO="https://github.com/ComplianceAsCode/content.git"
QUAY_IMAGE="quay.io/bapalm/k8scontent"
DOCKERFILE="Dockerfiles/ocp4_content"
CONTENT_REF="${1:-master}"
FORCE="${FORCE:-false}"

usage() {
	cat <<USAGE
Usage: $(basename "$0") [ref]

Build the ComplianceAsCode k8scontent image from source and push to quay.io/bapalm/k8scontent.

Arguments:
  ref    Git ref to build from (default: master)

Environment:
  FORCE=true    Rebuild even if the image already exists

The image is tagged with the source commit SHA (12 chars) and 'latest'.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

log_info "Cloning ComplianceAsCode/content (ref: $CONTENT_REF)..."
git clone --depth 1 --branch "$CONTENT_REF" "$CONTENT_REPO" "$WORK_DIR/content"

cd "$WORK_DIR/content"
COMMIT_SHA=$(git rev-parse HEAD)
SHORT_SHA="${COMMIT_SHA:0:12}"
COMMIT_DATE=$(git log -1 --format="%ai")
COMMIT_MSG=$(git log -1 --format="%s")

VERSION_TAG=$(git tag --points-at HEAD 2>/dev/null | grep "^v" | head -1 || true)

log_info "Source commit: $COMMIT_SHA"
log_info "Commit date: $COMMIT_DATE"
log_info "Commit message: $COMMIT_MSG"
if [[ -n "$VERSION_TAG" ]]; then
	log_info "Version tag: $VERSION_TAG"
fi

if [[ "$FORCE" != "true" ]] && command -v skopeo &>/dev/null; then
	if skopeo inspect --raw --no-creds "docker://${QUAY_IMAGE}:${SHORT_SHA}" &>/dev/null 2>&1; then
		log_info "Image ${QUAY_IMAGE}:${SHORT_SHA} already exists, skipping build"
		log_info "Set FORCE=true to rebuild"
		exit 0
	fi
fi

log_info "Building k8scontent image from $SHORT_SHA..."
if command -v docker &>/dev/null && docker buildx version &>/dev/null 2>&1; then
	log_info "Using docker buildx for multi-arch build (amd64 + arm64)"
	docker buildx build \
		-f "$DOCKERFILE" \
		--platform linux/amd64,linux/arm64 \
		--tag "${QUAY_IMAGE}:${SHORT_SHA}" \
		--tag "${QUAY_IMAGE}:latest" \
		--label "org.opencontainers.image.revision=${COMMIT_SHA}" \
		--label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		--label "org.opencontainers.image.source=https://github.com/ComplianceAsCode/content" \
		--label "org.opencontainers.image.title=k8scontent" \
		--push \
		.
elif command -v podman &>/dev/null; then
	log_info "Using podman (single arch)"
	podman build \
		-f "$DOCKERFILE" \
		--tag "${QUAY_IMAGE}:${SHORT_SHA}" \
		--tag "${QUAY_IMAGE}:latest" \
		--label "org.opencontainers.image.revision=${COMMIT_SHA}" \
		--label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		--label "org.opencontainers.image.source=https://github.com/ComplianceAsCode/content" \
		--label "org.opencontainers.image.title=k8scontent" \
		.
	log_info "Pushing ${QUAY_IMAGE}:${SHORT_SHA}..."
	podman push "${QUAY_IMAGE}:${SHORT_SHA}"
	log_info "Pushing ${QUAY_IMAGE}:latest..."
	podman push "${QUAY_IMAGE}:latest"
else
	log_error "Neither docker nor podman found"
	exit 1
fi

log_success "Built and pushed ${QUAY_IMAGE}:${SHORT_SHA}"
if [[ -n "$VERSION_TAG" ]]; then
	log_info "Content version: $VERSION_TAG"
fi
log_info "To use this image on a cluster:"
echo "  oc patch profilebundle ocp4 -n openshift-compliance --type merge -p '{\"spec\":{\"contentImage\":\"${QUAY_IMAGE}:${SHORT_SHA}\"}}'"
echo "  oc patch profilebundle rhcos4 -n openshift-compliance --type merge -p '{\"spec\":{\"contentImage\":\"${QUAY_IMAGE}:${SHORT_SHA}\"}}'"
