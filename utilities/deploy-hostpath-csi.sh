#!/bin/bash
# Deploy KubeVirt HostPath CSI Driver (standalone)
# This provides the same storage provisioner as CRC, which handles
# permissions correctly for restricted-v2 SCC pods.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

NAMESPACE="hostpath-provisioner"
STORAGE_CLASS_NAME="crc-csi-hostpath-provisioner"

# Check if already deployed and offer to reinstall
if oc get namespace "$NAMESPACE" &>/dev/null; then
	log_info "HostPath CSI Driver is already deployed"
	log_info "Reinstalling by deleting existing deployment first..."

	UTIL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	DELETE_SCRIPT="${UTIL_DIR}/delete-hostpath-csi.sh"

	if [ -f "$DELETE_SCRIPT" ]; then
		log_info "Running delete script..."
		bash "$DELETE_SCRIPT"
		log_info "Waiting 5 seconds before redeploying..."
		sleep 5
	else
		log_warn "delete-hostpath-csi.sh not found at $DELETE_SCRIPT"
		log_info "Manually cleaning up existing resources..."

		# Manual cleanup
		oc delete storageclass "$STORAGE_CLASS_NAME" --ignore-not-found=true
		oc delete daemonset csi-hostpathplugin -n "$NAMESPACE" --ignore-not-found=true
		oc delete csidriver kubevirt.io.hostpath-provisioner --ignore-not-found=true
		oc adm policy remove-scc-from-user privileged -z csi-hostpath-provisioner-sa -n "$NAMESPACE" 2>/dev/null || true
		oc delete clusterrolebinding hostpath-csi-provisioner-role --ignore-not-found=true
		oc delete clusterrole hostpath-external-provisioner-runner --ignore-not-found=true
		oc delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=60s || true
		log_info "Waiting 5 seconds before redeploying..."
		sleep 5
	fi
fi

# Function to check if an image exists in registry
check_image_exists() {
	local image=$1
	log_debug "Checking if image exists: $image"

	# Try to get image manifest without pulling the full image
	if podman manifest inspect "$image" &>/dev/null; then
		return 0
	elif skopeo inspect "docker://$image" &>/dev/null; then
		return 0
	else
		return 1
	fi
}

# Detect OpenShift cluster version for image tags
log_info "Detecting OpenShift cluster version..."
CLUSTER_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null | cut -d'.' -f1-2 || echo "")

if [[ -z "$CLUSTER_VERSION" ]]; then
	log_warn "Could not detect cluster version, defaulting to search from v4.19"
	CLUSTER_VERSION="4.19"
fi

# Extract major.minor (e.g., "4.17.1" -> "4.17")
log_info "Detected cluster version: ${CLUSTER_VERSION}"

# Parse version components
MAJOR=$(echo "$CLUSTER_VERSION" | cut -d'.' -f1)
MINOR=$(echo "$CLUSTER_VERSION" | cut -d'.' -f2)

# Define all required images
HOSTPATH_IMAGE_BASE="registry.redhat.io/container-native-virtualization/hostpath-csi-driver-rhel9"
NODE_REGISTRAR_IMAGE_BASE="registry.redhat.io/openshift4/ose-csi-node-driver-registrar"
LIVENESS_IMAGE_BASE="registry.redhat.io/openshift4/ose-csi-livenessprobe"
PROVISIONER_IMAGE_BASE="registry.redhat.io/openshift4/ose-csi-external-provisioner"

# Try to find the most recent compatible image version where ALL images exist
IMAGE_TAG=""

log_info "Searching for compatible image version (checking all required images)..."
for ((i = MINOR; i >= 15; i--)); do
	TEST_TAG="v${MAJOR}.${i}"

	log_debug "Testing version ${TEST_TAG}..."

	# Check if ALL required images exist for this version
	ALL_EXIST=true

	if ! check_image_exists "${HOSTPATH_IMAGE_BASE}:${TEST_TAG}"; then
		log_debug "- hostpath-csi-driver not found"
		ALL_EXIST=false
	fi

	if ! check_image_exists "${NODE_REGISTRAR_IMAGE_BASE}:${TEST_TAG}"; then
		log_debug "- ose-csi-node-driver-registrar not found"
		ALL_EXIST=false
	fi

	if ! check_image_exists "${LIVENESS_IMAGE_BASE}:${TEST_TAG}"; then
		log_debug "- ose-csi-livenessprobe not found"
		ALL_EXIST=false
	fi

	if ! check_image_exists "${PROVISIONER_IMAGE_BASE}:${TEST_TAG}"; then
		log_debug "- ose-csi-external-provisioner not found"
		ALL_EXIST=false
	fi

	if [ "$ALL_EXIST" = true ]; then
		IMAGE_TAG="$TEST_TAG"
		log_info "✓ Found compatible image version: ${IMAGE_TAG} (all images exist)"
		break
	else
		log_debug "Version ${TEST_TAG} incomplete, trying older version..."
	fi
done

# Fallback if no image found
if [[ -z "$IMAGE_TAG" ]]; then
	log_warn "Could not find compatible image by probing registry"
	log_warn "Defaulting to v4.19 (known working version)"
	IMAGE_TAG="v4.19"
fi

log_info "Using image tag: ${IMAGE_TAG} for all CSI components"

log_info "Deploying KubeVirt HostPath CSI Driver"
log_info "This is the same provisioner used by CRC"

# Create namespace
log_info "Creating namespace: $NAMESPACE"
oc create namespace "$NAMESPACE" 2>/dev/null || log_info "Namespace already exists"

# Create ServiceAccount
log_info "Creating ServiceAccount"
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csi-hostpath-provisioner-sa
  namespace: $NAMESPACE
EOF

# Create ClusterRole
log_info "Creating ClusterRole"
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: hostpath-external-provisioner-runner
rules:
- apiGroups: [""]
  resources: ["persistentvolumes"]
  verbs: ["get", "list", "watch", "create", "delete"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "update"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["list", "watch", "create", "update", "patch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["csinodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["volumeattachments"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["csistoragecapacities"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get"]
- apiGroups: ["apps"]
  resources: ["replicasets"]
  verbs: ["get"]
EOF

# Create ClusterRoleBinding
log_info "Creating ClusterRoleBinding"
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: hostpath-csi-provisioner-role
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: hostpath-external-provisioner-runner
subjects:
- kind: ServiceAccount
  name: csi-hostpath-provisioner-sa
  namespace: $NAMESPACE
EOF

# Grant privileged SCC (required for CSI driver)
log_info "Granting privileged SCC to CSI driver ServiceAccount"
oc adm policy add-scc-to-user privileged -z csi-hostpath-provisioner-sa -n "$NAMESPACE"

# Create CSIDriver
log_info "Creating CSIDriver resource"
cat <<EOF | oc apply -f -
apiVersion: storage.k8s.io/v1
kind: CSIDriver
metadata:
  name: kubevirt.io.hostpath-provisioner
spec:
  attachRequired: false
  podInfoOnMount: true
  volumeLifecycleModes:
  - Persistent
  fsGroupPolicy: File
EOF

# Create DaemonSet
log_info "Creating CSI DaemonSet"
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: csi-hostpathplugin
  namespace: $NAMESPACE
spec:
  selector:
    matchLabels:
      app.kubernetes.io/component: plugin
      app.kubernetes.io/instance: hostpath.csi.kubevirt.io
      app.kubernetes.io/name: csi-hostpathplugin
      app.kubernetes.io/part-of: csi-driver-host-path
  template:
    metadata:
      labels:
        app.kubernetes.io/component: plugin
        app.kubernetes.io/instance: hostpath.csi.kubevirt.io
        app.kubernetes.io/name: csi-hostpathplugin
        app.kubernetes.io/part-of: csi-driver-host-path
    spec:
      serviceAccountName: csi-hostpath-provisioner-sa
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      # Main CSI driver
      - name: hostpath-provisioner
        image: registry.redhat.io/container-native-virtualization/hostpath-csi-driver-rhel9:${IMAGE_TAG}
        imagePullPolicy: IfNotPresent
        args:
        - --drivername=kubevirt.io.hostpath-provisioner
        - --v=3
        - --datadir=[{"name":"local","path":"/csi-data-dir"}]
        - --endpoint=\$(CSI_ENDPOINT)
        - --nodeid=\$(NODE_NAME)
        - --version=latest
        env:
        - name: CSI_ENDPOINT
          value: unix:///csi/csi.sock
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: PV_DIR
          value: /var/hpvolumes
        - name: VERSION
          value: latest
        securityContext:
          privileged: true
        ports:
        - containerPort: 9898
          name: healthz
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /healthz
            port: 9898
          initialDelaySeconds: 10
          periodSeconds: 2
          timeoutSeconds: 3
          failureThreshold: 5
        volumeMounts:
        - name: csi-data-dir
          mountPath: /csi-data-dir
        - name: plugins-dir
          mountPath: /var/lib/kubelet/plugins
          mountPropagation: Bidirectional
        - name: mountpoint-dir
          mountPath: /var/lib/kubelet/pods
          mountPropagation: Bidirectional
        - name: socket-dir
          mountPath: /csi
      
      # Node driver registrar
      - name: node-driver-registrar
        image: registry.redhat.io/openshift4/ose-csi-node-driver-registrar:${IMAGE_TAG}
        imagePullPolicy: IfNotPresent
        args:
        - --v=3
        - --csi-address=/csi/csi.sock
        - --kubelet-registration-path=/var/lib/kubelet/plugins/csi-hostpath/csi.sock
        env:
        - name: KUBE_NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        securityContext:
          privileged: true
        volumeMounts:
        - name: socket-dir
          mountPath: /csi
        - name: registration-dir
          mountPath: /registration
        - name: csi-data-dir
          mountPath: /csi-data-dir
      
      # Liveness probe
      - name: liveness-probe
        image: registry.redhat.io/openshift4/ose-csi-livenessprobe:${IMAGE_TAG}
        imagePullPolicy: IfNotPresent
        args:
        - --csi-address=/csi/csi.sock
        - --health-port=9898
        volumeMounts:
        - name: socket-dir
          mountPath: /csi
      
      # CSI provisioner
      - name: csi-provisioner
        image: registry.redhat.io/openshift4/ose-csi-external-provisioner:${IMAGE_TAG}
        imagePullPolicy: IfNotPresent
        args:
        - --v=5
        - --csi-address=/csi/csi.sock
        - --feature-gates=Topology=true
        - --enable-capacity=true
        - --capacity-for-immediate-binding=true
        - --extra-create-metadata=true
        - --immediate-topology=false
        - --strict-topology=true
        - --node-deployment=true
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        securityContext:
          privileged: true
        volumeMounts:
        - name: socket-dir
          mountPath: /csi
      
      volumes:
      - name: socket-dir
        hostPath:
          path: /var/lib/kubelet/plugins/csi-hostpath
          type: DirectoryOrCreate
      - name: mountpoint-dir
        hostPath:
          path: /var/lib/kubelet/pods
          type: DirectoryOrCreate
      - name: registration-dir
        hostPath:
          path: /var/lib/kubelet/plugins_registry
          type: Directory
      - name: plugins-dir
        hostPath:
          path: /var/lib/kubelet/plugins
          type: Directory
      - name: csi-data-dir
        hostPath:
          path: /var/lib/csi-hostpath-data/
          type: DirectoryOrCreate
EOF

# Wait for DaemonSet to be ready
log_info "Waiting for CSI DaemonSet pods to be ready..."
sleep 5
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=csi-hostpathplugin -n "$NAMESPACE" --timeout=120s || {
	log_warn "CSI pods not ready yet, checking status..."
	oc get pods -n "$NAMESPACE"
}

# Create StorageClass
log_info "Creating StorageClass: $STORAGE_CLASS_NAME"
cat <<EOF | oc apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $STORAGE_CLASS_NAME
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubevirt.io.hostpath-provisioner
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: false
parameters:
  storagePool: local
EOF

# Remove default annotation from other StorageClasses
log_info "Removing default annotation from other StorageClasses"
for sc in $(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'); do
	if [ "$sc" != "$STORAGE_CLASS_NAME" ]; then
		log_info "Removing default from: $sc"
		oc patch storageclass "$sc" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
	fi
done

echo ""
echo "============================================"
log_success "KubeVirt HostPath CSI Driver deployed!"
echo "============================================"
echo ""
echo "CSI Driver Status:"
oc get pods -n "$NAMESPACE"
echo ""
echo "StorageClass:"
oc get storageclass "$STORAGE_CLASS_NAME"
echo ""
log_info "This provisioner handles permissions correctly for restricted-v2 SCC pods"
log_info "It's the same provisioner used by CRC"
