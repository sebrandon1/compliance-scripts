#!/bin/bash
set -euo pipefail

NAMESPACE="openshift-compliance"
OPERATOR_NAME="compliance-operator"
SUBSCRIPTION_NAME="compliance-operator-sub"

usage() {
	cat <<USAGE
Usage: $(basename "$0") [options]

Install the Compliance Operator into namespace '${NAMESPACE}' and ensure a usable default StorageClass.

Options:
  --co-ref <ref>                Git ref or release tag for Compliance Operator (default: latest release)
  -h, --help                    Show this help and exit

Notes:
  - The script will check for suitable storage and prompt to deploy HostPath CSI if needed.
  - Set KUBECONFIG to choose a specific cluster context, e.g.:
      KUBECONFIG=/path/to/kubeconfig $(basename "$0")
USAGE
}
while [[ $# -gt 0 ]]; do
	case "$1" in
	--co-ref)
		CO_REF="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		shift
		;;
	esac
done

# ============================================================================
# Storage Provisioner Check
# ============================================================================
echo "[PRECHECK] Checking for suitable storage provisioner..."

# Check if hostpath CSI driver is deployed (recommended)
HOSTPATH_CSI_DEPLOYED=false
if oc get csidriver kubevirt.io.hostpath-provisioner &>/dev/null; then
	echo "[INFO] ✅ KubeVirt HostPath CSI driver detected (recommended)"
	HOSTPATH_CSI_DEPLOYED=true
fi

# Check for default StorageClass
DEFAULT_SC=$(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || true)

if [[ -z "$DEFAULT_SC" ]] && [[ "$HOSTPATH_CSI_DEPLOYED" == "false" ]]; then
	echo ""
	echo "════════════════════════════════════════════════════════════════════"
	echo "📦 No default StorageClass detected - deploying HostPath CSI driver"
	echo "════════════════════════════════════════════════════════════════════"
	echo ""
	echo "[INFO] Deploying KubeVirt HostPath CSI driver (same as CRC uses)"
	echo "[INFO] This handles permissions correctly for restricted-v2 SCC"
	echo ""

	if [[ -x "./utilities/deploy-hostpath-csi.sh" ]]; then
		./utilities/deploy-hostpath-csi.sh
		echo ""
		echo "[SUCCESS] HostPath CSI driver deployed!"
		echo "[INFO] Continuing with Compliance Operator installation..."
		echo ""
	else
		echo "[ERROR] utilities/deploy-hostpath-csi.sh not found or not executable"
		echo "[INFO] Please run: ./utilities/deploy-hostpath-csi.sh"
		exit 1
	fi
elif [[ "$HOSTPATH_CSI_DEPLOYED" == "true" ]]; then
	echo "[INFO] ✅ HostPath CSI driver already deployed"
elif [[ -n "$DEFAULT_SC" ]]; then
	echo "[INFO] Default StorageClass found: $DEFAULT_SC"
	PROVISIONER=$(oc get storageclass "$DEFAULT_SC" -o jsonpath='{.provisioner}' 2>/dev/null || echo "unknown")
	if [[ "$PROVISIONER" == "kubevirt.io.hostpath-provisioner" ]]; then
		echo "[INFO] ✅ Using recommended KubeVirt HostPath CSI provisioner"
	elif [[ "$PROVISIONER" == "rancher.io/local-path" ]]; then
		echo "[WARN] ⚠️  local-path provisioner detected"
		echo "[WARN] This may have permission issues with restricted-v2 SCC"
		echo "[WARN] Consider running: ./utilities/deploy-hostpath-csi.sh"
	else
		echo "[INFO] Using provisioner: $PROVISIONER"
	fi
fi
echo ""

# ============================================================================
# Marketplace Health Check
# ============================================================================
echo "[PRECHECK] Ensuring 'openshift-marketplace' is healthy before proceeding..."
if ! oc get ns openshift-marketplace &>/dev/null; then
	echo "[ERROR] Namespace 'openshift-marketplace' not found. Ensure you're connected to an OpenShift cluster."
	exit 1
fi

echo "[PRECHECK] Checking for pods in error states in 'openshift-marketplace'..."
# Check for pods in permanent error states (ImagePullBackOff, CrashLoopBackOff, etc.)
ERROR_PODS=$(oc -n openshift-marketplace get pods -o json 2>/dev/null |
	jq -r '.items[] | select(.status.phase != "Succeeded" and .status.phase != "Running") | 
	select(.status.containerStatuses // [] | any(.state.waiting.reason | 
	test("ImagePullBackOff|ErrImagePull|CrashLoopBackOff|CreateContainerConfigError|InvalidImageName"))) | 
	.metadata.name' | tr '\n' ' ' || true)

if [[ -n "$ERROR_PODS" ]]; then
	echo "[ERROR] Found pods in permanent error states in 'openshift-marketplace':"
	oc -n openshift-marketplace get pods -o wide || true
	echo ""
	echo "Pods in error state: $ERROR_PODS"
	echo "[ERROR] Please resolve the pod errors above before proceeding."
	exit 1
fi

echo "[PRECHECK] Waiting up to 5m for non-completed pods in 'openshift-marketplace' to be Ready..."
# Poll for pods to be ready, handling pods that might be deleted/recreated during the wait
for i in {1..30}; do
	# Get current non-completed pods
	MKTPODS=$(oc -n openshift-marketplace get pods \
		-o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null || true)

	if [[ -z "$MKTPODS" ]]; then
		echo "[PRECHECK] No non-completed pods found in 'openshift-marketplace'"
		break
	fi

	ALL_READY=true
	while IFS= read -r line; do
		POD_NAME=$(echo "$line" | awk '{print $1}')

		# Check if pod still exists and is Ready
		if oc -n openshift-marketplace get pod "$POD_NAME" &>/dev/null; then
			if ! oc -n openshift-marketplace get pod "$POD_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
				ALL_READY=false
			fi
		fi
	done <<<"$MKTPODS"

	if [[ "$ALL_READY" == "true" ]]; then
		echo "[PRECHECK] All pods in 'openshift-marketplace' are Ready"
		break
	fi

	echo "[WAIT] Waiting for marketplace pods to be Ready ($i/30)..."
	sleep 10
done

# Final check - if pods are still not ready after timeout, fail
FAILED_PODS=$(oc -n openshift-marketplace get pods -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{" "}{.status.phase}{" "}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}' 2>/dev/null | grep -v "True$" || true)
if [[ -n "$FAILED_PODS" ]]; then
	echo "[ERROR] Some pods in 'openshift-marketplace' are not Ready. Current pod statuses:"
	oc -n openshift-marketplace get pods -o wide || true
	exit 1
fi

CO_REPO_OWNER="ComplianceAsCode"
CO_REPO_NAME="compliance-operator"
# Allow environment override via COMPLIANCE_OPERATOR_REF
CO_REF="${CO_REF:-${COMPLIANCE_OPERATOR_REF:-}}"
# Allow forcing community operator via USE_COMMUNITY_OPERATOR=true
USE_COMMUNITY="${USE_COMMUNITY_OPERATOR:-false}"

get_latest_release_tag() {
	curl -fsSL "https://api.github.com/repos/$CO_REPO_OWNER/$CO_REPO_NAME/releases/latest" 2>/dev/null |
		grep -m1 '"tag_name"' |
		sed -E 's/.*"tag_name"\s*:\s*"([^"]+)".*/\1/'
}

# ============================================================================
# Red Hat Certified Operator Check
# ============================================================================
# Prefer the Red Hat certified operator over the community version when available.
# The certified operator is more stable and doesn't use :latest (dev) images.
USE_REDHAT_OPERATOR=false

if [[ "$USE_COMMUNITY" == "true" ]]; then
	echo "[INFO] USE_COMMUNITY_OPERATOR=true - skipping Red Hat certified operator check"
else
	echo "[INFO] Checking for Red Hat certified operator availability..."

	# Check if redhat-operators catalog source exists
	if oc get catalogsource redhat-operators -n openshift-marketplace &>/dev/null; then
		echo "[INFO] ✅ redhat-operators catalog is available"

		# Check if compliance-operator package is available from redhat-operators
		RH_PACKAGE=$(oc get packagemanifests -n openshift-marketplace compliance-operator \
			-o jsonpath='{.status.catalogSource}' 2>/dev/null || true)

		if [[ "$RH_PACKAGE" == "redhat-operators" ]]; then
			echo "[INFO] ✅ Compliance Operator available from Red Hat certified catalog"
			USE_REDHAT_OPERATOR=true
		elif [[ -n "$RH_PACKAGE" ]]; then
			# Package exists but from different catalog - check if redhat-operators has it too
			RH_CHECK=$(oc get packagemanifests -n openshift-marketplace -o json 2>/dev/null |
				jq -r '.items[] | select(.metadata.name=="compliance-operator" and .status.catalogSource=="redhat-operators") | .metadata.name' || true)
			if [[ -n "$RH_CHECK" ]]; then
				echo "[INFO] ✅ Compliance Operator available from Red Hat certified catalog"
				USE_REDHAT_OPERATOR=true
			fi
		fi
	else
		# Check if redhat-operators is disabled in OperatorHub config
		RH_DISABLED=$(oc get operatorhub cluster -o jsonpath='{.status.sources[?(@.name=="redhat-operators")].disabled}' 2>/dev/null || true)
		if [[ "$RH_DISABLED" == "true" ]]; then
			echo "[WARN] redhat-operators catalog is disabled in OperatorHub"
			echo "[INFO] To enable: oc patch operatorhub cluster --type=merge -p '{\"spec\":{\"sources\":[{\"name\":\"redhat-operators\",\"disabled\":false}]}}'"
			echo "[INFO] Falling back to community operator..."
		else
			echo "[INFO] redhat-operators catalog not found, using community operator"
		fi
	fi
fi

# ============================================================================
# ARM Architecture Check
# ============================================================================
echo "[INFO] Checking cluster architecture..."
ARM_NODES=$(oc get nodes -o jsonpath='{.items[*].status.nodeInfo.architecture}' 2>/dev/null | tr ' ' '\n' | grep -c "arm64" || echo "0")

if [[ "$ARM_NODES" -gt 0 ]]; then
	echo "[INFO] Detected $ARM_NODES ARM64 node(s) in cluster"
	ARM_CLUSTER=true
else
	echo "[INFO] Detected x86_64 cluster"
	ARM_CLUSTER=false
fi

if [[ -z "$CO_REF" ]]; then
	echo "[INFO] Resolving latest $CO_REPO_OWNER/$CO_REPO_NAME release tag from GitHub..."
	CO_REF=$(get_latest_release_tag || true)
fi

if [[ -z "$CO_REF" ]]; then
	echo "[WARN] Could not determine latest release (rate limit or network issue). Falling back to 'master'."
	CO_REF="master"
else
	echo "[INFO] Using Compliance Operator ref: $CO_REF"
fi

# ============================================================================
# ARM Compatibility Check
# ============================================================================
if [[ "$ARM_CLUSTER" == "true" ]]; then
	# Check if version is earlier than v1.7.0 (which don't support ARM)
	# v1.7.0 is the ONLY version that supports ARM64
	if [[ "$CO_REF" =~ ^v1\.[0-6]\..*$ ]]; then
		echo ""
		echo "════════════════════════════════════════════════════════════════════"
		echo "❌ ERROR: ARM64 Incompatibility Detected"
		echo "════════════════════════════════════════════════════════════════════"
		echo ""
		echo "Compliance Operator $CO_REF does not support ARM64 architecture."
		echo ""
		echo "Your cluster has $ARM_NODES ARM64 node(s)."
		echo ""
		echo "Options:"
		echo "  1. Use v1.7.0 (the only ARM64-compatible version):"
		echo "     CO_REF=v1.7.0 $0"
		echo ""
		echo "  2. Use an x86_64 cluster"
		echo ""
		exit 1
	else
		echo "[INFO] ✅ Version $CO_REF is compatible with ARM64"
	fi
fi

BASE_RAW="https://raw.githubusercontent.com/$CO_REPO_OWNER/$CO_REPO_NAME/$CO_REF"

echo "[INFO] Creating namespace: $NAMESPACE"
oc apply -f "$BASE_RAW/config/ns/ns.yaml"

echo "[INFO] Compliance Operator will use default SCCs (restricted-v2)"
# DO NOT grant anyuid or privileged to compliance service accounts!
# The operator needs restricted-v2 SCC which auto-assigns UIDs from namespace range
# Granting anyuid/privileged breaks pods with runAsNonRoot: true

# ============================================================================
# Install Operator - Red Hat Certified or Community
# ============================================================================
if [[ "$USE_REDHAT_OPERATOR" == "true" ]]; then
	echo ""
	echo "════════════════════════════════════════════════════════════════════"
	echo "📦 Installing Red Hat Certified Compliance Operator"
	echo "════════════════════════════════════════════════════════════════════"
	echo ""
	echo "[INFO] Using Red Hat certified operator from redhat-operators catalog"
	echo "[INFO] This is more stable than the community version"
	echo ""

	# Create OperatorGroup
	echo "[INFO] Creating OperatorGroup"
	cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: compliance-operator
  namespace: $NAMESPACE
spec:
  targetNamespaces:
  - $NAMESPACE
EOF

	# Create Subscription to Red Hat certified operator
	echo "[INFO] Creating Subscription to Red Hat certified operator"
	cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: $SUBSCRIPTION_NAME
  namespace: $NAMESPACE
spec:
  channel: stable
  installPlanApproval: Automatic
  name: $OPERATOR_NAME
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

else
	echo ""
	echo "════════════════════════════════════════════════════════════════════"
	echo "📦 Installing Community Compliance Operator"
	echo "════════════════════════════════════════════════════════════════════"
	echo ""
	echo "[INFO] Using community operator from upstream catalog"
	echo "[INFO] Using catalog image tag: $CO_REF"
	echo ""

	echo "[INFO] Creating CatalogSource with master node tolerations"
	cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: compliance-operator
  namespace: openshift-marketplace
spec:
  displayName: Compliance Operator Upstream
  image: ghcr.io/complianceascode/compliance-operator-catalog:$CO_REF
  publisher: github.com/complianceascode/compliance-operator
  sourceType: grpc
  grpcPodConfig:
    tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
EOF

	echo "[INFO] Creating OperatorGroup"
	oc apply -f "$BASE_RAW/config/catalog/operator-group.yaml"

	echo "[INFO] Creating Subscription for Community Compliance Operator"
	oc apply -f "$BASE_RAW/config/catalog/subscription.yaml"
fi

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

# ============================================================================
# RBAC Fix: Ensure compliance-operator can create Jobs
# ============================================================================
# The upstream operator RBAC is missing 'create' permission for Jobs which
# prevents scans from launching. This supplements the missing permissions.
echo "[INFO] Applying supplemental RBAC for Job creation..."
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: compliance-operator-job-permissions
  namespace: $NAMESPACE
rules:
- apiGroups:
  - batch
  resources:
  - jobs
  verbs:
  - create
  - delete
  - get
  - list
  - watch
  - update
  - patch
EOF

cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: compliance-operator-job-permissions
  namespace: $NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: compliance-operator-job-permissions
subjects:
- kind: ServiceAccount
  name: compliance-operator
  namespace: $NAMESPACE
EOF
echo "[INFO] ✅ Supplemental RBAC applied"

# ============================================================================
# CRD Updates - Ensure CRDs have all required fields
# ============================================================================
# The v1.7.0 CRDs are missing the 'scannerType' field that the operator expects.
# Update the ComplianceScan CRD from master to fix "unknown field spec.scannerType" errors.
echo "[INFO] Updating ComplianceScan CRD to include scannerType field..."
SCAN_CRD_URL="https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/config/crd/bases/compliance.openshift.io_compliancescans.yaml"
if oc apply -f "$SCAN_CRD_URL" 2>/dev/null; then
	echo "[INFO] ✅ ComplianceScan CRD updated"
else
	echo "[WARN] Could not update ComplianceScan CRD - scans may get stuck in PENDING"
fi

# ============================================================================
# CustomRule CRD Check and Installation
# ============================================================================
echo "[INFO] Checking for CustomRule CRD..."
if ! oc get crd customrules.compliance.openshift.io &>/dev/null; then
	echo "[WARN] CustomRule CRD not found - attempting to install it..."

	# Try to apply from the same ref we're using for the operator
	CRD_URL="$BASE_RAW/deploy/crds/compliance.openshift.io_customrules.yaml"
	echo "[INFO] Attempting to apply CustomRule CRD from: $CRD_URL"

	if oc apply -f "$CRD_URL" 2>/dev/null; then
		echo "[SUCCESS] ✅ CustomRule CRD installed successfully"
	else
		echo "[WARN] Failed to apply from $CRD_URL, trying fallback locations..."

		# Try alternate paths that might exist
		# Note: The correct path is config/crd/bases/ (not deploy/crds/)
		FALLBACK_URLS=(
			"https://raw.githubusercontent.com/$CO_REPO_OWNER/$CO_REPO_NAME/master/config/crd/bases/compliance.openshift.io_customrules.yaml"
			"https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/config/crd/bases/compliance.openshift.io_customrules.yaml"
			"https://raw.githubusercontent.com/openshift/compliance-operator/master/config/crd/bases/compliance.openshift.io_customrules.yaml"
		)

		CRD_APPLIED=false
		for URL in "${FALLBACK_URLS[@]}"; do
			echo "[INFO] Trying: $URL"
			if oc apply -f "$URL" 2>/dev/null; then
				echo "[SUCCESS] ✅ CustomRule CRD installed from fallback location"
				CRD_APPLIED=true
				break
			fi
		done

		if [[ "$CRD_APPLIED" == "false" ]]; then
			echo "[WARN] ⚠️  Could not install CustomRule CRD from any known location"
			echo "[WARN] The operator may restart with cache sync errors"
			echo "[WARN] You can manually apply it later with:"
			echo "  oc apply -f https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/deploy/crds/compliance.openshift.io_customrules.yaml"
		fi
	fi

	# Verify the CRD was installed
	if oc get crd customrules.compliance.openshift.io &>/dev/null; then
		echo "[INFO] ✅ CustomRule CRD is now present"
	fi
else
	echo "[INFO] ✅ CustomRule CRD already exists"
fi
echo ""

echo "[INFO] Waiting up to 5m for non-completed pods in '$NAMESPACE' to be Ready..."
# Clean up any leftover storage probe pods first
oc -n "$NAMESPACE" delete pod -l app=co-storage-probe --ignore-not-found=true >/dev/null 2>&1 || true

for i in {1..30}; do
	# Get current non-completed, non-probe pods
	NSPODS=$(oc -n "$NAMESPACE" get pods \
		-o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null |
		grep -v "co-storage-probe" || true)

	if [[ -z "$NSPODS" ]]; then
		echo "[INFO] No non-completed pods found in '$NAMESPACE'"
		break
	fi

	# Count pods and check if any are not Ready
	NOT_READY=$(echo "$NSPODS" | wc -l | xargs)
	ALL_READY=true

	while IFS= read -r line; do
		POD_NAME=$(echo "$line" | awk '{print $1}')
		POD_PHASE=$(echo "$line" | awk '{print $2}')

		# Check if pod still exists and is Ready
		if oc -n "$NAMESPACE" get pod "$POD_NAME" &>/dev/null; then
			if ! oc -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
				ALL_READY=false
			fi
		fi
	done <<<"$NSPODS"

	if [[ "$ALL_READY" == "true" ]]; then
		echo "[INFO] All pods in '$NAMESPACE' are Ready"
		break
	fi

	echo "[WAIT] Waiting for pods to be Ready ($i/30)..."
	sleep 10
done

# Final status check
echo "[INFO] Final pod status in '$NAMESPACE':"
oc -n "$NAMESPACE" get pods -o wide 2>/dev/null || true

echo "[INFO] Waiting for ProfileBundles to become VALID..."
for i in {1..30}; do
	OCP4_STATUS=$(oc get profilebundle ocp4 -n "$NAMESPACE" -o jsonpath='{.status.dataStreamStatus}' 2>/dev/null || echo "")
	RHCOS4_STATUS=$(oc get profilebundle rhcos4 -n "$NAMESPACE" -o jsonpath='{.status.dataStreamStatus}' 2>/dev/null || echo "")

	if [[ "$OCP4_STATUS" == "VALID" && "$RHCOS4_STATUS" == "VALID" ]]; then
		echo "[INFO] All ProfileBundles are VALID"
		break
	fi
	echo "[WAIT] Waiting for ProfileBundles to be valid ($i/30)... ocp4=$OCP4_STATUS rhcos4=$RHCOS4_STATUS"
	sleep 10
done

echo "[INFO] ProfileBundle status:"
oc get profilebundles -n "$NAMESPACE" 2>/dev/null || true

echo "[INFO] Profile parser pods should be using 'restricted-v2' SCC"
echo "[INFO] You can verify with: oc get pods -n $NAMESPACE -o custom-columns=NAME:.metadata.name,SCC:.metadata.annotations.'openshift\.io/scc'"

echo "[NEXT STEP] To schedule a periodic compliance scan, run:"
echo "  ./core/apply-periodic-scan.sh"
