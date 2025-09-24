#!/bin/bash
set -euo pipefail

NAMESPACE="openshift-compliance"
OPERATOR_NAME="compliance-operator"
SUBSCRIPTION_NAME="compliance-operator-sub"

# Optional: choose storage bootstrap provider when no default SC exists: lvms|local-path|none
STORAGE_PROVIDER="lvms"
FORCE_STORAGE_BOOTSTRAP=false
while [[ $# -gt 0 ]]; do
	case "$1" in
		--storage)
			STORAGE_PROVIDER="$2"; shift 2;;
		--force-storage-bootstrap)
			FORCE_STORAGE_BOOTSTRAP=true; shift;;
		*)
			shift;;
	esac
done

echo "[PRECHECK] Ensuring 'openshift-marketplace' is healthy before proceeding..."
if ! oc get ns openshift-marketplace &>/dev/null; then
	echo "[ERROR] Namespace 'openshift-marketplace' not found. Ensure you're connected to an OpenShift cluster."
	exit 1
fi

echo "[PRECHECK] Waiting up to 5m for non-completed pods in 'openshift-marketplace' to be Ready..."
# Gather only pods that are not in Succeeded (Completed) phase (compatible with older bash)
MKTPODS=$(oc -n openshift-marketplace get pods -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | tr '\n' ' ' | xargs || true)
if [[ -n "$MKTPODS" ]]; then
	if ! oc -n openshift-marketplace wait --for=condition=Ready pod $MKTPODS --timeout=300s; then
		echo "[ERROR] Not all non-completed pods in 'openshift-marketplace' became Ready within the timeout. Current pod statuses:"
		oc -n openshift-marketplace get pods -o wide || true
		exit 1
	fi
else
	echo "[PRECHECK] No non-completed pods found in 'openshift-marketplace'; continuing."
fi

echo "[PRECHECK] Verifying a default StorageClass exists..."
# Try to find a default StorageClass via GA and beta annotations
DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
if [[ -z "$DEFAULT_SC" ]]; then
	DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
fi

# Detect presence of Rancher local-path SC regardless of default
RANCHER_SC_PRESENT=false
if oc get sc -o jsonpath='{range .items[*]}{.metadata.name}:{.provisioner}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="rancher.io/local-path"{found=1} END{exit !found}'; then
	RANCHER_SC_PRESENT=true
fi

if [[ -z "$DEFAULT_SC" || "$RANCHER_SC_PRESENT" == true || ( "$FORCE_STORAGE_BOOTSTRAP" == true && "$STORAGE_PROVIDER" != "none" ) ]]; then
    # If Rancher SC is present, prefer switching to LVMS automatically (no flags required)
    if [[ "$RANCHER_SC_PRESENT" == true ]]; then
        STORAGE_PROVIDER="lvms"
        echo "[WARN] Detected Rancher local-path StorageClass. Installing LVMS and switching default StorageClass."
    fi

	echo "[WARN] Bootstrapping storage using provider: $STORAGE_PROVIDER"
    case "$STORAGE_PROVIDER" in
        lvms)
            echo "[INFO] Ensuring Red Hat default catalog sources are enabled..."
            if ! oc get catalogsource redhat-operators -n openshift-marketplace &>/dev/null; then
                oc patch operatorhubs.config.openshift.io cluster --type merge -p '{"spec":{"disableAllDefaultSources":false}}' || true
                for i in {1..24}; do
                    if oc get catalogsource redhat-operators -n openshift-marketplace &>/dev/null; then
                        break
                    fi
                    sleep 5
                done
            fi

            echo "[INFO] Installing LVM Storage Operator (Red Hat)"
            # Ensure namespace exists
            if ! oc get ns openshift-storage &>/dev/null; then
                echo "[INFO] Creating namespace: openshift-storage"
                if ! oc create ns openshift-storage &>/dev/null; then
                    echo "[ERROR] Failed to create namespace 'openshift-storage'. Please create it and re-run."
                    exit 1
                fi
            fi

            # Determine LVMS channel (prefer defaultChannel if available)
            CHANNEL_LVMS=$(oc get packagemanifests -n openshift-marketplace lvms-operator -o jsonpath='{.status.defaultChannel}' 2>/dev/null || true)
            if [[ -z "$CHANNEL_LVMS" ]]; then
                # Fallback channel commonly available
                CHANNEL_LVMS="stable-4.19"
            fi

            cat <<YAML | oc apply -f -
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

            echo "[INFO] Waiting for LVMS Operator CSV to succeed..."
            for i in {1..30}; do
                CSV_LVMS=$(oc get subscription lvms-operator -n openshift-storage -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
                if [[ -n "$CSV_LVMS" ]]; then
                    PHASE_LVMS=$(oc get csv "$CSV_LVMS" -n openshift-storage -o jsonpath='{.status.phase}' 2>/dev/null || true)
                    echo "[WAIT] LVMS CSV: $CSV_LVMS phase=$PHASE_LVMS ($i/30)"
                    [[ "$PHASE_LVMS" == "Succeeded" ]] && break
                fi
                sleep 10
            done
            if [[ "${PHASE_LVMS:-}" != "Succeeded" ]]; then
                echo "[ERROR] LVMS Operator did not become ready. Skipping LVMS bootstrap."
                break
            fi

			echo "[INFO] LVMS Operator installed. Ensuring a StorageClass from LVMS exists..."
			# If there is already a topolvm-based SC, prefer it; otherwise create an LVMCluster
			if ! oc get sc -o jsonpath='{range .items[*]}{.metadata.name}:{.provisioner}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="topolvm.io"{found=1} END{exit !found}'; then
				cat <<'YAML' | oc apply -f -
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
				echo "[INFO] Waiting for a topolvm-based StorageClass to appear..."
				for i in {1..60}; do
					SC_LVMS=$(oc get sc -o jsonpath='{range .items[*]}{.metadata.name}:{.provisioner}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="topolvm.io"{print $1; exit}')
					if [[ -n "$SC_LVMS" ]]; then
						echo "[INFO] Found LVMS StorageClass: $SC_LVMS"
						break
					fi
					sleep 10
				done
				if [[ -z "${SC_LVMS:-}" ]]; then
					echo "[ERROR] No LVMS StorageClass detected. Ensure nodes have unused local disks."
					break
				fi
				# Set LVMS SC as default
				echo "[INFO] Marking '$SC_LVMS' as the default StorageClass"
				oc patch storageclass "$SC_LVMS" -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true
			fi

			echo "[INFO] LVMS storage bootstrap complete."
            ;;
		local-path)
			echo "[INFO] Installing local-path provisioner (lab use only) and setting default"
			oc apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
			oc -n local-path-storage rollout status deploy/local-path-provisioner --timeout=120s || true
			# OpenShift requires SCC for hostPath provisioners; grant privileged to SA
			oc adm policy add-scc-to-user privileged -z local-path-provisioner-service-account -n local-path-storage || true
			oc patch storageclass local-path -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}' || true
			;;
		none|*)
			echo "[ERROR] No default StorageClass and storage bootstrap disabled (provider=$STORAGE_PROVIDER)."
            echo "[HINT] Install a dynamic provisioner (e.g., LVMS/ODF/NFS) and re-run."
			exit 1
			;;
	esac
	# Re-detect default SC after bootstrap
	DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
	if [[ -z "$DEFAULT_SC" ]]; then
		echo "[ERROR] Failed to establish a default StorageClass. Please configure cluster storage and retry."
		exit 1
	fi
fi
echo "[INFO] Default StorageClass detected: $DEFAULT_SC"

# If we bootstrapped storage, optionally remove Rancher local-path provisioner to avoid confusion
if [[ "$STORAGE_PROVIDER" == "lvms" ]]; then
	if oc get sc local-path &>/dev/null; then
		# Re-detect default after attempted LSO bootstrap
		DEFAULT_SC=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
		if [[ "$DEFAULT_SC" != "local-path" && -n "$DEFAULT_SC" ]]; then
			echo "[CLEANUP] Removing Rancher local-path provisioner and StorageClass"
			oc delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml || true
			oc delete sc local-path --ignore-not-found=true || true
			# Best-effort: remove privileged SCC grant to the SA
			oc adm policy remove-scc-from-user privileged -z local-path-provisioner-service-account -n local-path-storage || true
		fi
	fi
fi

echo "[INFO] Creating namespace: $NAMESPACE"
oc apply -f https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/config/ns/ns.yaml

echo "[INFO] Creating OperatorGroup"
oc apply -f https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/config/catalog/catalog-source.yaml

echo "[INFO] Subscribing to Compliance Operator from Red Hat"
oc apply -f https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/config/catalog/operator-group.yaml

echo "[INFO] Creating Subscription for Compliance Operator"
oc apply -f https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/config/catalog/subscription.yaml

echo "[INFO] Waiting for Subscription to populate installedCSV..."
for i in {1..30}; do
	echo "Attempt number $i"
	CSV=$(oc get subscription $SUBSCRIPTION_NAME -n $NAMESPACE -o jsonpath='{.status.installedCSV}' || true)
	if [[ -n "$CSV" ]]; then
		echo "[INFO] Found installedCSV: $CSV"
		break
	fi
	echo "[WAIT] installedCSV not found yet, retrying... ($i/30)"
	sleep 10
done

if [[ -z "$CSV" ]]; then
	echo "[ERROR] installedCSV was not populated. Exiting."
	exit 1
fi

echo "[INFO] Waiting for ClusterServiceVersion ($CSV) to be succeeded..."
for i in {1..30}; do
	PHASE=$(oc get clusterserviceversion "$CSV" -n "$NAMESPACE" -o jsonpath='{.status.phase}' || true)
	echo "[WAIT] ClusterServiceVersion phase: $PHASE ($i/30)"
	if [[ "$PHASE" == "Succeeded" ]]; then
		echo "[INFO] ClusterServiceVersion $CSV is Succeeded."
		break
	fi
	sleep 10
done

if [[ "$PHASE" != "Succeeded" ]]; then
	echo "[ERROR] ClusterServiceVersion $CSV did not reach Succeeded phase. Exiting."
	exit 1
fi

echo "[SUCCESS] Compliance Operator installed successfully."
oc get pods -n $NAMESPACE

echo "[NEXT STEP] To schedule a periodic compliance scan, run:"
echo "  ./apply-periodic-scan.sh"
