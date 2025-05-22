#!/bin/bash
set -euo pipefail

NAMESPACE="openshift-compliance"

# Create the ScanSetting YAML
cat <<EOF | oc apply -f -
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSetting
metadata:
  name: periodic-setting
  namespace: $NAMESPACE
schedule: "0 1 * * *"
rawResultStorage:
    size: "2Gi"
    rotation: 5
roles:
  - worker
  - master
EOF

# Create the ScanSettingBinding YAML
cat <<EOF | oc apply -f -
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: periodic-e8
  namespace: $NAMESPACE
profiles:
  - name: rhcos4-e8
    kind: Profile
    apiGroup: compliance.openshift.io/v1alpha1
  - name: ocp4-e8
    kind: Profile
    apiGroup: compliance.openshift.io/v1alpha1
settingsRef:
  name: periodic-setting
  kind: ScanSetting
  apiGroup: compliance.openshift.io/v1alpha1
EOF

echo "[INFO] ScanSetting 'periodic-setting' and ScanSettingBinding 'periodic-e8' applied in namespace '$NAMESPACE'."
