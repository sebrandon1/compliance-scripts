#!/bin/bash
set -euo pipefail

NAMESPACE="openshift-compliance"
OPERATOR_NAME="compliance-operator"

# Delete the Compliance Operator Subscription
if oc get subscription $OPERATOR_NAME -n $NAMESPACE &>/dev/null; then
  echo "[INFO] Deleting Subscription: $OPERATOR_NAME"
  oc delete subscription $OPERATOR_NAME -n $NAMESPACE
else
  echo "[INFO] Subscription $OPERATOR_NAME not found. Skipping."
fi

# Delete the OperatorGroup
if oc get operatorgroup -n $NAMESPACE &>/dev/null; then
  echo "[INFO] Deleting OperatorGroup in $NAMESPACE"
  oc delete operatorgroup --all -n $NAMESPACE
else
  echo "[INFO] No OperatorGroup found in $NAMESPACE. Skipping."
fi

# Delete the CatalogSource
if oc get catalogsource -n $NAMESPACE &>/dev/null; then
  echo "[INFO] Deleting CatalogSource in $NAMESPACE"
  oc delete catalogsource --all -n $NAMESPACE
else
  echo "[INFO] No CatalogSource found in $NAMESPACE. Skipping."
fi

# Delete the ClusterServiceVersion
CSV=$(oc get csv -n $NAMESPACE -o name | grep $OPERATOR_NAME || true)
if [[ -n "$CSV" ]]; then
  echo "[INFO] Deleting ClusterServiceVersion: $CSV"
  oc delete $CSV -n $NAMESPACE
else
  echo "[INFO] No ClusterServiceVersion found for $OPERATOR_NAME. Skipping."
fi

# Delete the Namespace
if oc get namespace $NAMESPACE &>/dev/null; then
  echo "[INFO] Deleting Namespace: $NAMESPACE"
  oc delete namespace $NAMESPACE
else
  echo "[INFO] Namespace $NAMESPACE not found. Skipping."
fi

echo "[SUCCESS] Compliance Operator and related resources have been deleted."
