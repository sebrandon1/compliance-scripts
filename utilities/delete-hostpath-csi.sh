#!/bin/bash
# Delete KubeVirt HostPath CSI Driver
# Cleans up all resources created by deploy-hostpath-csi.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

NAMESPACE="hostpath-provisioner"
STORAGE_CLASS_NAME="crc-csi-hostpath-provisioner"

log_info "Deleting KubeVirt HostPath CSI Driver"

# Delete StorageClass
log_info "Deleting StorageClass: $STORAGE_CLASS_NAME"
oc delete storageclass "$STORAGE_CLASS_NAME" --ignore-not-found=true

# Delete DaemonSet
log_info "Deleting CSI DaemonSet"
oc delete daemonset csi-hostpathplugin -n "$NAMESPACE" --ignore-not-found=true

# Wait for pods to terminate
log_info "Waiting for CSI pods to terminate..."
oc wait --for=delete pod -l app.kubernetes.io/name=csi-hostpathplugin -n "$NAMESPACE" --timeout=60s 2>/dev/null || log_info "Pods already deleted"

# Delete CSIDriver
log_info "Deleting CSIDriver resource"
oc delete csidriver kubevirt.io.hostpath-provisioner --ignore-not-found=true

# Remove privileged SCC
log_info "Removing privileged SCC from CSI driver ServiceAccount"
oc adm policy remove-scc-from-user privileged -z csi-hostpath-provisioner-sa -n "$NAMESPACE" 2>/dev/null || log_info "SCC already removed"

# Delete ClusterRoleBinding
log_info "Deleting ClusterRoleBinding"
oc delete clusterrolebinding hostpath-csi-provisioner-role --ignore-not-found=true

# Delete ClusterRole
log_info "Deleting ClusterRole"
oc delete clusterrole hostpath-external-provisioner-runner --ignore-not-found=true

# Delete ServiceAccount
log_info "Deleting ServiceAccount"
oc delete serviceaccount csi-hostpath-provisioner-sa -n "$NAMESPACE" --ignore-not-found=true

# Delete namespace
log_info "Deleting namespace: $NAMESPACE"
oc delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=60s || {
	log_warn "Namespace deletion taking longer than expected"
	log_info "You may need to check for finalizers if namespace is stuck"
}

echo ""
echo "============================================"
log_success "KubeVirt HostPath CSI Driver deleted!"
echo "============================================"
echo ""
