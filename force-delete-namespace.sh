#!/bin/bash
set -euo pipefail

NAMESPACE="${1:-openshift-compliance}"

echo "[INFO] Checking if namespace '$NAMESPACE' is stuck in Terminating..."
STATUS=$(oc get ns "$NAMESPACE" -o jsonpath='{.status.phase}' || echo "NotFound")

if [[ "$STATUS" != "Terminating" ]]; then
  echo "[INFO] Namespace '$NAMESPACE' is not terminating. Status: $STATUS"
  exit 0
fi

echo "[INFO] Exporting namespace definition to ns.json..."
oc get namespace "$NAMESPACE" -o json > ns.json

echo "[INFO] Removing finalizers..."
jq 'del(.spec.finalizers)' ns.json > ns-cleaned.json

API_URL=$(oc config view --minify -o jsonpath='{.clusters[0].cluster.server}')
TOKEN=$(oc whoami -t)

echo "[INFO] Sending API request to remove finalizers and finalize deletion..."
curl -k -s -X PUT "$API_URL/api/v1/namespaces/$NAMESPACE/finalize" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @ns-cleaned.json

echo "[INFO] Waiting for namespace to be deleted..."
for i in {1..30}; do
  if ! oc get ns "$NAMESPACE" &>/dev/null; then
    echo "[SUCCESS] Namespace '$NAMESPACE' has been deleted."
    exit 0
  fi
  echo "[WAIT] Namespace still exists, retrying... ($i/30)"
  sleep 5
done

echo "[ERROR] Namespace '$NAMESPACE' was not deleted after timeout."
exit 1
