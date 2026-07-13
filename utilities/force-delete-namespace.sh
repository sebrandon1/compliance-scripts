#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
	echo "Usage: $(basename "$0") [namespace]"
	echo ""
	echo "Force-delete a namespace stuck in Terminating state by removing finalizers."
	echo "Defaults to the compliance namespace if not specified."
	exit 0
}

[[ "${1:-}" =~ ^(-h|--help)$ ]] && usage

NAMESPACE="${1:-$(get_compliance_namespace)}"

log_info "Checking if namespace '$NAMESPACE' is stuck in Terminating..."
STATUS=$(oc get ns "$NAMESPACE" -o jsonpath='{.status.phase}' || echo "NotFound")

if [[ "$STATUS" != "Terminating" ]]; then
	log_info "Namespace '$NAMESPACE' is not terminating. Status: $STATUS"
	exit 0
fi

log_info "Exporting namespace definition to ns.json..."
oc get namespace "$NAMESPACE" -o json >ns.json

log_info "Removing finalizers..."
jq 'del(.spec.finalizers)' ns.json >ns-cleaned.json

API_URL=$(oc config view --minify -o jsonpath='{.clusters[0].cluster.server}')
TOKEN=$(oc whoami -t)

log_info "Sending API request to remove finalizers and finalize deletion..."
curl -k -s -X PUT "$API_URL/api/v1/namespaces/$NAMESPACE/finalize" \
	-H "Authorization: Bearer $TOKEN" \
	-H "Content-Type: application/json" \
	--data-binary @ns-cleaned.json

log_info "Waiting for namespace to be deleted..."
for i in {1..30}; do
	if ! oc get ns "$NAMESPACE" &>/dev/null; then
		log_success "Namespace '$NAMESPACE' has been deleted."
		exit 0
	fi
	log_info "Namespace still exists, retrying... ($i/30)"
	sleep 5
done

log_error "Namespace '$NAMESPACE' was not deleted after timeout."
exit 1
