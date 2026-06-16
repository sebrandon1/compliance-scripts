#!/bin/bash
# update-marketplace-versions.sh - Discover available community-operator-index
# tags and update the OPENSHIFT_MARKETPLACE_IMAGES array in verify-images.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

VERIFY_IMAGES="$SCRIPT_DIR/utilities/verify-images.sh"
REGISTRY="registry.redhat.io"
QUERY_REGISTRY="registry.access.redhat.com"
IMAGE="redhat/community-operator-index"
WINDOW=10
DRY_RUN=false

usage() {
	cat <<USAGE
Usage: $(basename "$0") [options]

Discover available community-operator-index tags on $REGISTRY and update
the OPENSHIFT_MARKETPLACE_IMAGES array in utilities/verify-images.sh.

Keeps the most recent $WINDOW OCP minor versions.

Options:
  --dry-run    Show what would change without modifying any files
  --window N   Number of OCP minor versions to keep (default: $WINDOW)
  -h, --help   Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--dry-run)
		DRY_RUN=true
		shift
		;;
	--window)
		WINDOW="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		log_error "Unknown option: $1"
		usage
		exit 1
		;;
	esac
done

require_cmd skopeo

log_info "Querying tags for $QUERY_REGISTRY/$IMAGE..."
RAW_TAGS=$(skopeo list-tags "docker://$QUERY_REGISTRY/$IMAGE" 2>/dev/null)

if [[ -z "$RAW_TAGS" ]]; then
	log_error "Failed to fetch tags from $QUERY_REGISTRY/$IMAGE"
	exit 1
fi

VERSIONS=$(echo "$RAW_TAGS" | jq -r '.Tags[]' |
	grep -E '^v4\.[0-9]+$' |
	sort -t. -k2 -n)

if [[ -z "$VERSIONS" ]]; then
	log_error "No v4.XX tags found"
	exit 1
fi

log_info "Available OCP versions:"
echo "$VERSIONS" | while read -r v; do echo "  $v"; done

LATEST=$(echo "$VERSIONS" | tail -n "$WINDOW")

log_info "Keeping last $WINDOW versions:"
echo "$LATEST" | while read -r v; do echo "  $v"; done

NEW_ARRAY="OPENSHIFT_MARKETPLACE_IMAGES=("
while read -r tag; do
	NEW_ARRAY+=$'\n\t'"\"$REGISTRY/$IMAGE:$tag\""
done <<<"$LATEST"
NEW_ARRAY+=$'\n'")"

CURRENT_ARRAY=$(sed -n '/^OPENSHIFT_MARKETPLACE_IMAGES=(/,/^)/p' "$VERIFY_IMAGES")

if [[ "$CURRENT_ARRAY" == "$NEW_ARRAY" ]]; then
	log_success "Already up to date — no changes needed"
	echo "updated=false"
	exit 0
fi

log_info "Changes detected:"
diff <(echo "$CURRENT_ARRAY") <(echo "$NEW_ARRAY") || true

if [[ "$DRY_RUN" == "true" ]]; then
	log_warn "Dry run — no files modified"
	echo "updated=true"
	exit 0
fi

REPLACEMENT_FILE=$(mktemp)
trap 'rm -f "$REPLACEMENT_FILE"' EXIT
printf '%s\n' "$NEW_ARRAY" >"$REPLACEMENT_FILE"

TEMPFILE=$(mktemp)
{
	skip=false
	while IFS= read -r line; do
		if [[ "$line" == "OPENSHIFT_MARKETPLACE_IMAGES=("* ]]; then
			cat "$REPLACEMENT_FILE"
			skip=true
			continue
		fi
		if [[ "$skip" == "true" ]]; then
			[[ "$line" == ")" ]] && skip=false
			continue
		fi
		printf '%s\n' "$line"
	done <"$VERIFY_IMAGES"
} >"$TEMPFILE"

rm -f "$REPLACEMENT_FILE"
mv "$TEMPFILE" "$VERIFY_IMAGES"
chmod +x "$VERIFY_IMAGES"

log_success "Updated $VERIFY_IMAGES"
echo "updated=true"
