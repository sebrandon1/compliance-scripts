#!/bin/bash
# detect-co-release.sh - Print the latest Compliance Operator release tag
#
# Usage:
#   ./scripts/detect-co-release.sh
#
# Uses the GitHub CLI when available (honors GH_TOKEN), falling back to the
# REST API. Prints the tag on stdout and exits non-zero when no tag can be
# determined, so callers never receive an empty reference.
#
# Environment:
#   GH_TOKEN         Token for authenticated GitHub API calls (recommended)
#   GITHUB_API_URL   API base URL (default: https://api.github.com)
#
# Requires: jq, and either gh or curl

set -euo pipefail

REPO="ComplianceAsCode/compliance-operator"
API_URL="${GITHUB_API_URL:-https://api.github.com}"
# Newest vX.Y.Z tag from the tags list; releases/latest is preferred when set.
TAG_SELECT='[.[].name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))]
	| sort_by(split(".") | map(ltrimstr("v") | tonumber))
	| last // empty'

if ! command -v jq >/dev/null 2>&1; then
	echo "Error: jq is required" >&2
	exit 1
fi

fetch() {
	if command -v gh >/dev/null 2>&1; then
		gh api "repos/${REPO}/$1" 2>/dev/null || true
	else
		curl -fsSL "${API_URL}/repos/${REPO}/$1" 2>/dev/null || true
	fi
}

CO_REF=$(fetch "releases/latest" | jq -r '.tag_name // empty' 2>/dev/null || true)
if [[ -z "$CO_REF" ]]; then
	CO_REF=$(fetch "tags?per_page=100" | jq -r "$TAG_SELECT" 2>/dev/null || true)
fi

if [[ -z "$CO_REF" ]]; then
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
		echo "::error::Could not detect the latest Compliance Operator release"
	else
		echo "Error: Could not detect the latest Compliance Operator release" >&2
	fi
	exit 1
fi

echo "$CO_REF"
