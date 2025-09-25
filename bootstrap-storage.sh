#!/bin/bash
set -euo pipefail

# This script ensures a sane default StorageClass exists for the cluster.
# It can bootstrap storage using LVMS (TopoLVM) or Rancher local-path for labs.
# All operational logs are sent to stderr. The detected default StorageClass
# name is printed to stdout as the final line for easy capture by callers.

STORAGE_PROVIDER="lvms"       # lvms | local-path | none
FORCE_STORAGE_BOOTSTRAP=false  # when true, perform bootstrap even if a default SC exists
PROBE_NAMESPACE="openshift-compliance"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --storage)
      STORAGE_PROVIDER="$2"; shift 2;;
    --force-storage-bootstrap)
      FORCE_STORAGE_BOOTSTRAP=true; shift;;
    --namespace)
      PROBE_NAMESPACE="$2"; shift 2;;
    *)
      # ignore unknown flags for forward-compat
      shift;;
  esac
done

echo "[PRECHECK] Verifying a default StorageClass exists..." >&2
# Try to find a default StorageClass via GA and beta annotations
DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
if [[ -z "${DEFAULT_SC}" ]]; then
  DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
fi

# Detect presence of Rancher local-path SC regardless of default
RANCHER_SC_PRESENT=false
if oc get sc -o jsonpath='{range .items[*]}{.metadata.name}:{.provisioner}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="rancher.io/local-path"{found=1} END{exit !found}'; then
  RANCHER_SC_PRESENT=true
fi

bootstrap_needed=false
if [[ -z "${DEFAULT_SC}" || "${RANCHER_SC_PRESENT}" == true || ( "${FORCE_STORAGE_BOOTSTRAP}" == true && "${STORAGE_PROVIDER}" != "none" ) ]]; then
  bootstrap_needed=true
fi

if [[ "${bootstrap_needed}" == true ]]; then
  echo "[WARN] Bootstrapping storage using provider: ${STORAGE_PROVIDER}" >&2

  case "${STORAGE_PROVIDER}" in
    lvms)
      echo "[INFO] Ensuring Red Hat default catalog sources are enabled..." >&2
      if ! oc get catalogsource redhat-operators -n openshift-marketplace &>/dev/null; then
        oc patch operatorhubs.config.openshift.io cluster --type merge -p '{"spec":{"disableAllDefaultSources":false}}' >/dev/null || true
        for i in {1..24}; do
          if oc get catalogsource redhat-operators -n openshift-marketplace &>/dev/null; then
            break
          fi
          sleep 5
        done
      fi

      echo "[INFO] Installing LVM Storage Operator (Red Hat)" >&2
      # Ensure namespace exists
      if ! oc get ns openshift-storage &>/dev/null; then
        echo "[INFO] Creating namespace: openshift-storage" >&2
        if ! oc create ns openshift-storage &>/dev/null; then
          echo "[ERROR] Failed to create namespace 'openshift-storage'. Please create it and re-run." >&2
          exit 1
        fi
      fi

      # Determine LVMS channel (prefer defaultChannel if available)
      CHANNEL_LVMS=$(oc get packagemanifests -n openshift-marketplace lvms-operator -o jsonpath='{.status.defaultChannel}' 2>/dev/null || true)
      if [[ -z "${CHANNEL_LVMS}" ]]; then
        CHANNEL_LVMS="stable-4.19"
      fi

      cat <<YAML | oc apply -f - >/dev/null
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-storage-og
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: lvms-operator
  namespace: openshift-storage
spec:
  channel: ${CHANNEL_LVMS}
  name: lvms-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
YAML

      echo "[INFO] Waiting for LVMS Operator CSV to succeed..." >&2
      for i in {1..30}; do
        CSV_LVMS=$(oc get subscription lvms-operator -n openshift-storage -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
        if [[ -n "${CSV_LVMS}" ]]; then
          PHASE_LVMS=$(oc get csv "${CSV_LVMS}" -n openshift-storage -o jsonpath='{.status.phase}' 2>/dev/null || true)
          echo "[WAIT] LVMS CSV: ${CSV_LVMS} phase=${PHASE_LVMS} (${i}/30)" >&2
          [[ "${PHASE_LVMS}" == "Succeeded" ]] && break
        fi
        sleep 10
      done
      if [[ "${PHASE_LVMS:-}" != "Succeeded" ]]; then
        echo "[ERROR] LVMS Operator did not become ready. Skipping LVMS bootstrap." >&2
        exit 1
      fi

      echo "[INFO] LVMS Operator installed. Ensuring a StorageClass from LVMS exists..." >&2
      # If there is already a topolvm-based SC, prefer it; otherwise create an LVMCluster
      if ! oc get sc -o jsonpath='{range .items[*]}{.metadata.name}:{.provisioner}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="topolvm.io"{found=1} END{exit !found}'; then
        cat <<'YAML' | oc apply -f - >/dev/null
apiVersion: lvm.topolvm.io/v1alpha1
kind: LVMCluster
metadata:
  name: lvmcluster
  namespace: openshift-storage
spec:
  storage:
    deviceClasses:
    - name: vg1
      default: true
      fstype: xfs
      thinPoolConfig:
        name: thin-pool
        sizePercent: 90
        overprovisionRatio: 10
YAML
        echo "[INFO] Waiting for a topolvm-based StorageClass to appear..." >&2
        for i in {1..60}; do
          SC_LVMS=$(oc get sc -o jsonpath='{range .items[*]}{.metadata.name}:{.provisioner}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="topolvm.io"{print $1; exit}')
          if [[ -n "${SC_LVMS}" ]]; then
            echo "[INFO] Found LVMS StorageClass: ${SC_LVMS}" >&2
            break
          fi
          sleep 10
        done
        if [[ -z "${SC_LVMS:-}" ]]; then
          echo "[ERROR] No LVMS StorageClass detected. Ensure nodes have unused local disks." >&2
          exit 1
        fi
        # Set LVMS SC as default
        echo "[INFO] Marking '${SC_LVMS}' as the default StorageClass" >&2
        oc patch storageclass "${SC_LVMS}" -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null || true
      fi
      ;;

    

    local-path)
      echo "[INFO] Installing local-path provisioner (lab use only) and setting default" >&2
      oc apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml >/dev/null
      oc -n local-path-storage rollout status deploy/local-path-provisioner --timeout=120s >/dev/null || true
      # OpenShift requires SCC for hostPath provisioners; grant privileged to SA
      oc adm policy add-scc-to-user privileged -z local-path-provisioner-service-account -n local-path-storage >/dev/null || true
      oc patch storageclass local-path -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}' >/dev/null || true
      ;;

    none|*)
      echo "[ERROR] No default StorageClass and storage bootstrap disabled (provider=${STORAGE_PROVIDER})." >&2
      echo "[HINT] Install a dynamic provisioner (e.g., LVMS/ODF) and re-run." >&2
      exit 1
      ;;
  esac

  # Re-detect default SC after bootstrap
  DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
  if [[ -z "${DEFAULT_SC}" ]]; then
    DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
  fi
  if [[ -z "${DEFAULT_SC}" ]]; then
    echo "[ERROR] Failed to establish a default StorageClass. Please configure cluster storage and retry." >&2
    exit 1
  fi

  # If we bootstrapped storage via LVMS, optionally remove Rancher local-path provisioner to avoid confusion
  if [[ "${STORAGE_PROVIDER}" == "lvms" ]]; then
    if oc get sc local-path &>/dev/null; then
      # Re-detect default
      DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
      if [[ "${DEFAULT_SC}" != "local-path" && -n "${DEFAULT_SC}" ]]; then
        echo "[CLEANUP] Removing Rancher local-path provisioner and StorageClass" >&2
        oc delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml >/dev/null || true
        oc delete sc local-path --ignore-not-found=true >/dev/null || true
        oc adm policy remove-scc-from-user privileged -z local-path-provisioner-service-account -n local-path-storage >/dev/null || true
      fi
    fi
  fi
fi

echo "[INFO] Default StorageClass detected: ${DEFAULT_SC}" >&2

# Optional LVMS capacity probe (only meaningful for node-local LVMS)
SC_PROVISIONER=$(oc get sc "${DEFAULT_SC}" -o jsonpath='{.provisioner}' 2>/dev/null || true)
if [[ "${SC_PROVISIONER}" == "topolvm.io" ]]; then
  echo "[VALIDATE] Probing storage capacity on default SC '${DEFAULT_SC}' (provisioner=${SC_PROVISIONER})..." >&2
  # Ensure namespace exists before probes
  oc get ns "${PROBE_NAMESPACE}" >/dev/null 2>&1 || oc create ns "${PROBE_NAMESPACE}" >/dev/null 2>&1 || true

  _probe_pvc() {
    local size="$1"
    local name="co-storage-probe-$(echo "$size" | tr '[:upper:]' '[:lower:]')"
    oc -n "${PROBE_NAMESPACE}" delete pod ${name} --ignore-not-found=true >/dev/null 2>&1 || true
    oc -n "${PROBE_NAMESPACE}" delete pvc ${name} --ignore-not-found=true >/dev/null 2>&1 || true
    oc -n "${PROBE_NAMESPACE}" wait --for=delete pod/${name} --timeout=30s >/dev/null 2>&1 || true
    oc -n "${PROBE_NAMESPACE}" wait --for=delete pvc/${name} --timeout=30s >/dev/null 2>&1 || true
    cat <<YAML | oc apply -n "${PROBE_NAMESPACE}" -f - >/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${name}
  labels:
    app: co-storage-probe
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: ${DEFAULT_SC}
  resources:
    requests:
      storage: ${size}
YAML
    cat <<YAML | oc apply -n "${PROBE_NAMESPACE}" -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  labels:
    app: co-storage-probe
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  tolerations:
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  restartPolicy: Never
  containers:
  - name: pause
    image: registry.k8s.io/pause:3.9
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
      seccompProfile:
        type: RuntimeDefault
    volumeMounts:
    - name: vol
      mountPath: /data
  volumes:
  - name: vol
    persistentVolumeClaim:
      claimName: ${name}
YAML
    if ! oc -n "${PROBE_NAMESPACE}" wait --for=condition=Ready pod/${name} --timeout=180s >/dev/null 2>&1; then
      echo "[ERROR] Storage probe failed for size=${size}. PVC did not bind/schedule using SC '${DEFAULT_SC}'." >&2
      echo "[HINT] Ensure LVMS has free VG capacity on at least one schedulable node, or choose a different SC." >&2
      return 1
    fi
    oc -n "${PROBE_NAMESPACE}" delete pod ${name} --ignore-not-found=true >/dev/null 2>&1 || true
    oc -n "${PROBE_NAMESPACE}" delete pvc ${name} --ignore-not-found=true >/dev/null 2>&1 || true
    echo "[OK] Storage probe succeeded for ${size}." >&2
  }

  _probe_pvc "512Mi" || { echo "[FATAL] Insufficient storage for 512Mi PVCs. Aborting storage bootstrap." >&2; exit 1; }
  _probe_pvc "1Gi" || echo "[WARN] 1Gi PVC could not bind. Larger profiles may fail unless you increase LVMS capacity." >&2
else
  echo "[SKIP] Skipping LVMS storage probe for non-LVMS SC '${DEFAULT_SC}' (provisioner=${SC_PROVISIONER})." >&2
fi

# Output ONLY the default StorageClass name to stdout for consumption by callers
echo "${DEFAULT_SC}"


