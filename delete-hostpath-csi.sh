#!/bin/bash
# Delete KubeVirt HostPath CSI Driver
# Cleans up all resources created by deploy-hostpath-csi.sh

set -e

NAMESPACE="hostpath-provisioner"
STORAGE_CLASS_NAME="crc-csi-hostpath-provisioner"

echo "[INFO] Deleting KubeVirt HostPath CSI Driver"

# Delete StorageClass
echo "[INFO] Deleting StorageClass: $STORAGE_CLASS_NAME"
oc delete storageclass "$STORAGE_CLASS_NAME" --ignore-not-found=true

# Delete DaemonSet
echo "[INFO] Deleting CSI DaemonSet"
oc delete daemonset csi-hostpathplugin -n "$NAMESPACE" --ignore-not-found=true

# Wait for pods to terminate
echo "[INFO] Waiting for CSI pods to terminate..."
oc wait --for=delete pod -l app.kubernetes.io/name=csi-hostpathplugin -n "$NAMESPACE" --timeout=60s 2>/dev/null || echo "[INFO] Pods already deleted"

# Delete CSIDriver
echo "[INFO] Deleting CSIDriver resource"
oc delete csidriver kubevirt.io.hostpath-provisioner --ignore-not-found=true

# Remove privileged SCC
echo "[INFO] Removing privileged SCC from CSI driver ServiceAccount"
oc adm policy remove-scc-from-user privileged -z csi-hostpath-provisioner-sa -n "$NAMESPACE" 2>/dev/null || echo "[INFO] SCC already removed"

# Delete ClusterRoleBinding
echo "[INFO] Deleting ClusterRoleBinding"
oc delete clusterrolebinding hostpath-csi-provisioner-role --ignore-not-found=true

# Delete ClusterRole
echo "[INFO] Deleting ClusterRole"
oc delete clusterrole hostpath-external-provisioner-runner --ignore-not-found=true

# Delete ServiceAccount
echo "[INFO] Deleting ServiceAccount"
oc delete serviceaccount csi-hostpath-provisioner-sa -n "$NAMESPACE" --ignore-not-found=true

# Delete namespace
echo "[INFO] Deleting namespace: $NAMESPACE"
oc delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=60s || {
  echo "[WARN] Namespace deletion taking longer than expected"
  echo "[INFO] You may need to check for finalizers if namespace is stuck"
}

echo ""
echo "============================================"
echo "[SUCCESS] KubeVirt HostPath CSI Driver deleted!"
echo "============================================"
echo ""

