#!/bin/bash
set -euo pipefail

NAMESPACE="openshift-compliance"
OPERATOR_NAME="compliance-operator"
SUBSCRIPTION_NAME="compliance-operator-sub"

echo "[INFO] Creating namespace: $NAMESPACE"
oc apply -f https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/config/ns/ns.yaml

echo "[INFO] Creating OperatorGroup"
oc apply -f https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/config/catalog/catalog-source.yaml

echo "[INFO] Subscribing to Compliance Operator from Red Hat"
oc apply -f https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/config/catalog/operator-group.yaml

echo "[INFO] Creating Subscription for Compliance Operator"
oc apply -f https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/config/catalog/subscription.yaml

echo "[INFO] Waiting for Subscription to populate installedCSV..."
for i in {1..30}; do
  echo "Attempt number $i"
  CSV=$(oc get subscription $SUBSCRIPTION_NAME -n $NAMESPACE -o jsonpath='{.status.installedCSV}' || true)
  if [[ -n "$CSV" ]]; then
    echo "[INFO] Found installedCSV: $CSV"
    break
  fi
  echo "[WAIT] installedCSV not found yet, retrying... ($i/30)"
  sleep 10
done

if [[ -z "$CSV" ]]; then
  echo "[ERROR] installedCSV was not populated. Exiting."
  exit 1
fi

echo "[INFO] Waiting for ClusterServiceVersion ($CSV) to be succeeded..."
for i in {1..30}; do
  PHASE=$(oc get clusterserviceversion "$CSV" -n "$NAMESPACE" -o jsonpath='{.status.phase}' || true)
  echo "[WAIT] ClusterServiceVersion phase: $PHASE ($i/30)"
  if [[ "$PHASE" == "Succeeded" ]]; then
    echo "[INFO] ClusterServiceVersion $CSV is Succeeded."
    break
  fi
  sleep 10
done

if [[ "$PHASE" != "Succeeded" ]]; then
  echo "[ERROR] ClusterServiceVersion $CSV did not reach Succeeded phase. Exiting."
  exit 1
fi

echo "[SUCCESS] Compliance Operator installed successfully."
oc get pods -n $NAMESPACE

echo "[NEXT STEP] To schedule a periodic compliance scan, run:"
echo "  ./apply-periodic-scan.sh"
