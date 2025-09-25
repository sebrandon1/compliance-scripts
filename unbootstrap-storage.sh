#!/bin/bash
set -euo pipefail

# This script attempts to undo storage bootstrap actions performed by bootstrap-storage.sh
# Supported providers: LVMS (TopoLVM) and Rancher local-path
# - Logs go to stderr; resulting default StorageClass (if any) printed to stdout

PROVIDER="auto"   # auto | lvms | local-path

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      PROVIDER="$2"; shift 2;;
    *)
      shift;;
  esac
done

echo "[INFO] Starting unbootstrap (provider=${PROVIDER})" >&2

delete_local_path() {
  echo "[CLEANUP] Removing Rancher local-path provisioner & SC (best-effort)" >&2
  oc delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml >/dev/null 2>&1 || true
  oc delete sc local-path --ignore-not-found=true >/dev/null 2>&1 || true
  oc adm policy remove-scc-from-user privileged -z local-path-provisioner-service-account -n local-path-storage >/dev/null 2>&1 || true
}

delete_lvms() {
  echo "[CLEANUP] Removing LVMS LVMCluster (best-effort)" >&2
  oc delete LVMCluster lvmcluster -n openshift-storage >/dev/null 2>&1 || true

  echo "[CLEANUP] Clearing default annotation on TopoLVM StorageClasses (best-effort)" >&2
  while IFS= read -r sc; do
    [[ -z "$sc" ]] && continue
    oc patch sc "$sc" --type merge -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' >/dev/null 2>&1 || true
  done < <(oc get sc -o jsonpath='{range .items[?(@.provisioner=="topolvm.io")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

  # Uninstall LVMS operator and related OLM resources (best-effort)
  echo "[INFO] Attempting to remove LVMS Subscription and CSV (best-effort)" >&2
  CSV_NAME=$(oc get subscription lvms-operator -n openshift-storage -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
  oc delete subscription lvms-operator -n openshift-storage >/dev/null 2>&1 || true
  if [[ -n "${CSV_NAME}" ]]; then
    oc delete csv "${CSV_NAME}" -n openshift-storage >/dev/null 2>&1 || true
  else
    # Fallback: try to find any LVMS/TopoLVM related CSVs in the namespace
    while IFS= read -r csv; do
      [[ -z "$csv" ]] && continue
      oc delete csv "$csv" -n openshift-storage >/dev/null 2>&1 || true
    done < <(oc get csv -n openshift-storage -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.displayName}{"\n"}{end}' 2>/dev/null | awk '/lvms|LVM|topolvm|TopoLVM/ {print $1}' || true)
  fi

  # Remove CRDs owned by LVMS (group=lvm.topolvm.io)
  echo "[CLEANUP] Removing LVMS CRDs (best-effort)" >&2
  while IFS= read -r crd; do
    [[ -n "$crd" ]] || continue
    oc delete crd "$crd" >/dev/null 2>&1 || true
  done < <(oc get crds -o jsonpath='{range .items[?(@.spec.group=="lvm.topolvm.io")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

  # Remove OperatorGroup if no other subscriptions remain in namespace
  if [[ -n $(oc get operatorgroup openshift-storage-og -n openshift-storage -o name 2>/dev/null || true) ]]; then
    SUB_COUNT=$(oc get subscriptions.operators.coreos.com -n openshift-storage --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    if [[ "${SUB_COUNT}" == "0" ]]; then
      echo "[CLEANUP] Removing OperatorGroup 'openshift-storage-og' (best-effort)" >&2
      oc delete operatorgroup openshift-storage-og -n openshift-storage >/dev/null 2>&1 || true
    else
      echo "[SKIP] OperatorGroup retained: other subscriptions detected in 'openshift-storage'." >&2
    fi
  fi
}

if [[ "$PROVIDER" == "local-path" || "$PROVIDER" == "auto" ]]; then
  # Check for local-path SC presence
  if oc get sc local-path >/dev/null 2>&1 || oc get sc -o jsonpath='{range .items[*]}{.provisioner}{"\n"}{end}' 2>/dev/null | grep -q '^rancher.io/local-path$'; then
    delete_local_path
  fi
fi

if [[ "$PROVIDER" == "lvms" || "$PROVIDER" == "auto" ]]; then
  # Check for LVMS SCs, LVMCluster, or lingering LVMS Subscription
  if oc get sc -o jsonpath='{range .items[*]}{.provisioner}{"\n"}{end}' 2>/dev/null | grep -q '^topolvm.io$' \
     || oc get LVMCluster lvmcluster -n openshift-storage >/dev/null 2>&1 \
     || oc get subscription lvms-operator -n openshift-storage >/dev/null 2>&1; then
    delete_lvms
  fi
fi

 

# Determine resulting default SC
DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
if [[ -z "${DEFAULT_SC}" ]]; then
  DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
fi

if [[ -n "${DEFAULT_SC}" ]]; then
  echo "[INFO] Default StorageClass after unbootstrap: ${DEFAULT_SC}" >&2
else
  echo "[WARN] No default StorageClass set after unbootstrap." >&2
fi

echo "${DEFAULT_SC}"


