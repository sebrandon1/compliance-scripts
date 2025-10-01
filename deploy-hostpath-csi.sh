#!/bin/bash
# Deploy KubeVirt HostPath CSI Driver (standalone)
# This provides the same storage provisioner as CRC, which handles
# permissions correctly for restricted-v2 SCC pods.

set -e

NAMESPACE="hostpath-provisioner"
STORAGE_CLASS_NAME="crc-csi-hostpath-provisioner"

# Detect OpenShift cluster version for image tags
echo "[INFO] Detecting OpenShift cluster version..."
CLUSTER_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null | cut -d'.' -f1-2 || echo "")

if [[ -z "$CLUSTER_VERSION" ]]; then
    echo "[WARN] Could not detect cluster version, defaulting to v4.15"
    IMAGE_TAG="v4.15"
else
    # Extract major.minor (e.g., "4.17.1" -> "v4.17")
    IMAGE_TAG="v${CLUSTER_VERSION}"
    echo "[INFO] Detected cluster version: ${CLUSTER_VERSION}, using image tag: ${IMAGE_TAG}"
fi

echo "[INFO] Deploying KubeVirt HostPath CSI Driver"
echo "[INFO] This is the same provisioner used by CRC"

# Create namespace
echo "[INFO] Creating namespace: $NAMESPACE"
oc create namespace "$NAMESPACE" 2>/dev/null || echo "[INFO] Namespace already exists"

# Create ServiceAccount
echo "[INFO] Creating ServiceAccount"
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csi-hostpath-provisioner-sa
  namespace: $NAMESPACE
EOF

# Create ClusterRole
echo "[INFO] Creating ClusterRole"
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
echo "[INFO] Creating ClusterRoleBinding"
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
echo "[INFO] Granting privileged SCC to CSI driver ServiceAccount"
oc adm policy add-scc-to-user privileged -z csi-hostpath-provisioner-sa -n "$NAMESPACE"

# Create CSIDriver
echo "[INFO] Creating CSIDriver resource"
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
echo "[INFO] Creating CSI DaemonSet"
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
echo "[INFO] Waiting for CSI DaemonSet pods to be ready..."
sleep 5
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=csi-hostpathplugin -n "$NAMESPACE" --timeout=120s || {
  echo "[WARN] CSI pods not ready yet, checking status..."
  oc get pods -n "$NAMESPACE"
}

# Create StorageClass
echo "[INFO] Creating StorageClass: $STORAGE_CLASS_NAME"
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
echo "[INFO] Removing default annotation from other StorageClasses"
for sc in $(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'); do
  if [ "$sc" != "$STORAGE_CLASS_NAME" ]; then
    echo "[INFO] Removing default from: $sc"
    oc patch storageclass "$sc" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
  fi
done

echo ""
echo "============================================"
echo "[SUCCESS] KubeVirt HostPath CSI Driver deployed!"
echo "============================================"
echo ""
echo "CSI Driver Status:"
oc get pods -n "$NAMESPACE"
echo ""
echo "StorageClass:"
oc get storageclass "$STORAGE_CLASS_NAME"
echo ""
echo "[INFO] This provisioner handles permissions correctly for restricted-v2 SCC pods"
echo "[INFO] It's the same provisioner used by CRC"

