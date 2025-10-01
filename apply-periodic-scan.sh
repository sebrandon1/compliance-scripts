#!/bin/bash
set -euo pipefail

NAMESPACE="openshift-compliance"
# Allow running without PVCs
NO_PVC=${NO_PVC:-false}

# Parse optional flags
while [[ ${#} -gt 0 ]]; do
  case "${1}" in
    --no-pvc)
      NO_PVC=true; shift;;
    --namespace|-n)
      NAMESPACE="${2}"; shift 2;;
    --help|-h)
      echo "Usage: $0 [--no-pvc] [--namespace NAMESPACE]"; exit 0;;
    *)
      shift;;
  esac
done
if [[ "${NO_PVC}" != "true" ]]; then
  # Use default StorageClass; prefer crc-csi-hostpath-provisioner; else first SC. Allow env override.
  if [[ -z "${SC_NAME:-}" ]]; then
    # First, try to get the default StorageClass
    SC_NAME=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || true)
    
    # If no default, prefer crc-csi-hostpath-provisioner (recommended)
    if [[ -z "${SC_NAME:-}" ]] && oc get sc crc-csi-hostpath-provisioner &>/dev/null; then
      SC_NAME=crc-csi-hostpath-provisioner
    fi
    
    # Fall back to any available StorageClass
    if [[ -z "${SC_NAME:-}" ]]; then
      SC_NAME=$(oc get sc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    fi
  fi
  # Storage defaults aligned with CRD defaults
  RAW_SIZE=${RAW_SIZE:-1Gi}
  ROTATION=${ROTATION:-3}
fi

# Create the ScanSetting YAML
cat <<EOF | oc apply -f -
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSetting
metadata:
  name: periodic-setting
  namespace: $NAMESPACE
schedule: "0 1 * * *"
$(
  if [[ "${NO_PVC}" != "true" ]]; then
    cat <<YML
rawResultStorage:
    storageClassName: ${SC_NAME}
    size: "${RAW_SIZE}"
    rotation: ${ROTATION}
    tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
    - key: node.kubernetes.io/not-ready
      operator: Exists
      effect: NoExecute
      tolerationSeconds: 300
    - key: node.kubernetes.io/unreachable
      operator: Exists
      effect: NoExecute
      tolerationSeconds: 300
    - key: node.kubernetes.io/memory-pressure
      operator: Exists
      effect: NoSchedule
YML
  fi
)
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

echo "[ACTION REQUIRED] To continue, please run: ./create-scan.sh"
