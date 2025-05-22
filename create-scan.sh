#!/bin/bash
set -euo pipefail

NAMESPACE="openshift-compliance"
PROFILE="ocp4-cis"
SCAN_NAME="cis-scan"

# Create a ScanSettingBinding YAML
cat <<EOF | oc apply -f -
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: $SCAN_NAME
  namespace: $NAMESPACE
profiles:
- apiGroup: compliance.openshift.io/v1alpha1
  kind: Profile
  name: $PROFILE
  namespace: $NAMESPACE
settingsRef:
  apiGroup: compliance.openshift.io/v1alpha1
  kind: ScanSetting
  name: default
EOF

echo "[INFO] ScanSettingBinding '$SCAN_NAME' created in namespace '$NAMESPACE'."

echo "[INFO] You can check the scan status with:"
echo "  oc get compliancescan -n $NAMESPACE"
