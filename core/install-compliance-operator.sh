#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

NAMESPACE="$DEFAULT_COMPLIANCE_NAMESPACE"
OPERATOR_NAME="compliance-operator"
SUBSCRIPTION_NAME="compliance-operator-sub"

# Pinned image overrides for reproducible scanning.
# Set these env vars to override, or leave empty to use upstream defaults.
PINNED_OPERATOR_IMAGE="${RELATED_IMAGE_OPERATOR:-quay.io/bapalm/compliance-operator:234bdd200637}"
PINNED_OPENSCAP_IMAGE="${RELATED_IMAGE_OPENSCAP:-quay.io/bapalm/openscap-ocp:234bdd200637}"
PINNED_CONTENT_IMAGE="${RELATED_IMAGE_PROFILE:-quay.io/bapalm/k8scontent:v0.1.80}"

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
log_info "Checking for suitable storage provisioner..."

# Check if hostpath CSI driver is deployed (recommended)
HOSTPATH_CSI_DEPLOYED=false
if oc get csidriver kubevirt.io.hostpath-provisioner &>/dev/null; then
	log_info "✅ KubeVirt HostPath CSI driver detected (recommended)"
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
	log_info "Deploying KubeVirt HostPath CSI driver (same as CRC uses)"
	log_info "This handles permissions correctly for restricted-v2 SCC"
	echo ""

	if [[ -x "./utilities/deploy-hostpath-csi.sh" ]]; then
		./utilities/deploy-hostpath-csi.sh
		echo ""
		log_success "HostPath CSI driver deployed!"
		log_info "Continuing with Compliance Operator installation..."
		echo ""
	else
		log_error "utilities/deploy-hostpath-csi.sh not found or not executable"
		log_info "Please run: ./utilities/deploy-hostpath-csi.sh"
		exit 1
	fi
elif [[ "$HOSTPATH_CSI_DEPLOYED" == "true" ]]; then
	log_info "✅ HostPath CSI driver already deployed"
elif [[ -n "$DEFAULT_SC" ]]; then
	log_info "Default StorageClass found: $DEFAULT_SC"
	PROVISIONER=$(oc get storageclass "$DEFAULT_SC" -o jsonpath='{.provisioner}' 2>/dev/null || echo "unknown")
	if [[ "$PROVISIONER" == "kubevirt.io.hostpath-provisioner" ]]; then
		log_info "✅ Using recommended KubeVirt HostPath CSI provisioner"
	elif [[ "$PROVISIONER" == "rancher.io/local-path" ]]; then
		log_warn "⚠️  local-path provisioner detected"
		log_warn "This may have permission issues with restricted-v2 SCC"
		log_warn "Consider running: ./utilities/deploy-hostpath-csi.sh"
	else
		log_info "Using provisioner: $PROVISIONER"
	fi
fi
echo ""

# ============================================================================
# Marketplace Health Check
# ============================================================================
log_info "Ensuring 'openshift-marketplace' is healthy before proceeding..."
if ! oc get ns openshift-marketplace &>/dev/null; then
	log_error "Namespace 'openshift-marketplace' not found. Ensure you're connected to an OpenShift cluster."
	exit 1
fi

log_info "Checking for pods in error states in 'openshift-marketplace'..."
# Check for pods in permanent error states (ImagePullBackOff, CrashLoopBackOff, etc.)
ERROR_PODS=$(oc -n openshift-marketplace get pods -o json 2>/dev/null |
	jq -r '.items[] | select(.status.phase != "Succeeded" and .status.phase != "Running") | 
	select(.status.containerStatuses // [] | any(.state.waiting.reason | 
	test("ImagePullBackOff|ErrImagePull|CrashLoopBackOff|CreateContainerConfigError|InvalidImageName"))) | 
	.metadata.name' | tr '\n' ' ' || true)

if [[ -n "$ERROR_PODS" ]]; then
	log_error "Found pods in permanent error states in 'openshift-marketplace':"
	oc -n openshift-marketplace get pods -o wide || true
	echo ""
	echo "Pods in error state: $ERROR_PODS"
	log_error "Please resolve the pod errors above before proceeding."
	exit 1
fi

log_info "Waiting up to 5m for non-completed pods in 'openshift-marketplace' to be Ready..."
# Poll for pods to be ready, handling pods that might be deleted/recreated during the wait
for i in {1..30}; do
	# Get current non-completed pods
	MKTPODS=$(oc -n openshift-marketplace get pods \
		-o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null || true)

	if [[ -z "$MKTPODS" ]]; then
		log_info "No non-completed pods found in 'openshift-marketplace'"
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
		log_info "All pods in 'openshift-marketplace' are Ready"
		break
	fi

	log_info "Waiting for marketplace pods to be Ready ($i/30)..."
	sleep 10
done

# Final check - if pods are still not ready after timeout, fail
# Ignore pods created less than 30 seconds ago to avoid race conditions with catalog reconciliation
NOW_TS=$(date +%s)
FAILED_PODS=""
while IFS= read -r line; do
	POD_NAME=$(echo "$line" | awk '{print $1}')
	POD_PHASE=$(echo "$line" | awk '{print $2}')
	POD_READY=$(echo "$line" | awk '{print $3}')

	# Skip if pod name is empty
	[[ -z "$POD_NAME" ]] && continue

	# Check pod creation time
	POD_CREATED=$(oc -n openshift-marketplace get pod "$POD_NAME" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || true)
	if [[ -n "$POD_CREATED" ]]; then
		# Convert ISO 8601 timestamp to epoch
		POD_TS=$(date -d "$POD_CREATED" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$POD_CREATED" +%s 2>/dev/null || echo "0")
		AGE=$((NOW_TS - POD_TS))
		if [[ $AGE -lt 30 ]]; then
			log_info "Ignoring recently created pod '$POD_NAME' (${AGE}s old) - catalog reconciliation in progress"
			continue
		fi
	fi

	# Pod is old enough, check if it's not ready
	if [[ "$POD_READY" != "True" ]]; then
		FAILED_PODS="$FAILED_PODS $POD_NAME"
	fi
done < <(oc -n openshift-marketplace get pods -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{" "}{.status.phase}{" "}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}' 2>/dev/null || true)

if [[ -n "$FAILED_PODS" ]]; then
	log_error "Some pods in 'openshift-marketplace' are not Ready:$FAILED_PODS"
	log_error "Current pod statuses:"
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
	log_info "USE_COMMUNITY_OPERATOR=true - skipping Red Hat certified operator check"
else
	log_info "Checking for Red Hat certified operator availability..."

	# Check if redhat-operators catalog source exists
	if oc get catalogsource redhat-operators -n openshift-marketplace &>/dev/null; then
		log_info "✅ redhat-operators catalog is available"

		# Check if compliance-operator package is available from redhat-operators
		RH_PACKAGE=$(oc get packagemanifests -n openshift-marketplace compliance-operator \
			-o jsonpath='{.status.catalogSource}' 2>/dev/null || true)

		if [[ "$RH_PACKAGE" == "redhat-operators" ]]; then
			log_info "✅ Compliance Operator available from Red Hat certified catalog"
			USE_REDHAT_OPERATOR=true
		elif [[ -n "$RH_PACKAGE" ]]; then
			# Package exists but from different catalog - check if redhat-operators has it too
			RH_CHECK=$(oc get packagemanifests -n openshift-marketplace -o json 2>/dev/null |
				jq -r '.items[] | select(.metadata.name=="compliance-operator" and .status.catalogSource=="redhat-operators") | .metadata.name' || true)
			if [[ -n "$RH_CHECK" ]]; then
				log_info "✅ Compliance Operator available from Red Hat certified catalog"
				USE_REDHAT_OPERATOR=true
			fi
		fi
	else
		# Check if redhat-operators is disabled in OperatorHub config
		RH_DISABLED=$(oc get operatorhub cluster -o jsonpath='{.status.sources[?(@.name=="redhat-operators")].disabled}' 2>/dev/null || true)
		if [[ "$RH_DISABLED" == "true" ]]; then
			log_warn "redhat-operators catalog is disabled in OperatorHub"
			log_info "To enable: oc patch operatorhub cluster --type=merge -p '{\"spec\":{\"sources\":[{\"name\":\"redhat-operators\",\"disabled\":false}]}}'"
			log_info "Falling back to community operator..."
		else
			log_info "redhat-operators catalog not found, using community operator"
		fi
	fi
fi

# ============================================================================
# ARM Architecture Check
# ============================================================================
log_info "Checking cluster architecture..."
ARM_NODES=$(oc get nodes -o jsonpath='{.items[*].status.nodeInfo.architecture}' 2>/dev/null | tr ' ' '\n' | grep -c "arm64" || true)
ARM_NODES=${ARM_NODES:-0}

if [[ "$ARM_NODES" -gt 0 ]]; then
	log_info "Detected $ARM_NODES ARM64 node(s) in cluster"
	ARM_CLUSTER=true
else
	log_info "Detected x86_64 cluster"
	ARM_CLUSTER=false
fi

if [[ -z "$CO_REF" ]]; then
	log_info "Resolving latest $CO_REPO_OWNER/$CO_REPO_NAME release tag from GitHub..."
	CO_REF=$(get_latest_release_tag || true)
fi

if [[ -z "$CO_REF" ]]; then
	log_warn "Could not determine latest release (rate limit or network issue). Falling back to 'master'."
	CO_REF="master"
else
	log_info "Using Compliance Operator ref: $CO_REF"
fi

# ============================================================================
# ARM Compatibility Check
# ============================================================================
if [[ "$ARM_CLUSTER" == "true" ]]; then
	# Check if version is earlier than v1.7.0 (which don't support ARM)
	# v1.7.0+ supports ARM64 (v1.7.0, v1.8.x, etc.)
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
		echo "  1. Use v1.7.0 or later (ARM64-compatible versions):"
		echo "     CO_REF=v1.7.0 $0"
		echo "     CO_REF=v1.8.2 $0"
		echo ""
		echo "  2. Use an x86_64 cluster"
		echo ""
		exit 1
	else
		log_info "✅ Version $CO_REF is compatible with ARM64"
	fi
fi

BASE_RAW="https://raw.githubusercontent.com/$CO_REPO_OWNER/$CO_REPO_NAME/$CO_REF"

log_info "Creating namespace: $NAMESPACE"
oc apply -f "$BASE_RAW/config/ns/ns.yaml"

log_info "Compliance Operator will use default SCCs (restricted-v2)"
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
	log_info "Using Red Hat certified operator from redhat-operators catalog"
	log_info "This is more stable than the community version"
	echo ""

	# Create OperatorGroup
	log_info "Creating OperatorGroup"
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
	log_info "Creating Subscription to Red Hat certified operator"
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
	log_info "Using community operator from upstream catalog"
	log_info "Using catalog image tag: $CO_REF"
	echo ""

	# Determine catalog image: try upstream ghcr.io first, fall back to quay.io/bapalm mirror
	CATALOG_IMAGE="ghcr.io/complianceascode/compliance-operator-catalog:$CO_REF"
	MIRROR_IMAGE="quay.io/bapalm/compliance-operator-catalog:$CO_REF"

	log_info "Checking if upstream catalog image is available..."
	if command -v skopeo &>/dev/null && skopeo inspect --raw --no-creds "docker://$CATALOG_IMAGE" &>/dev/null 2>&1; then
		log_info "Using upstream catalog image: $CATALOG_IMAGE"
	elif command -v skopeo &>/dev/null && skopeo inspect --raw --no-creds "docker://$MIRROR_IMAGE" &>/dev/null 2>&1; then
		log_info "Upstream image not found, using mirror: $MIRROR_IMAGE"
		CATALOG_IMAGE="$MIRROR_IMAGE"
	else
		log_warn "skopeo not available to verify images, using mirror: $MIRROR_IMAGE"
		CATALOG_IMAGE="$MIRROR_IMAGE"
	fi

	log_info "Creating CatalogSource with master node tolerations"
	cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: compliance-operator
  namespace: openshift-marketplace
spec:
  displayName: Compliance Operator Upstream
  image: $CATALOG_IMAGE
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

	log_info "Waiting for CatalogSource to be READY..."
	for i in {1..30}; do
		CATALOG_STATE=$(oc get catalogsource compliance-operator -n openshift-marketplace -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null || echo "")
		if [[ "$CATALOG_STATE" == "READY" ]]; then
			log_info "CatalogSource is READY"
			break
		fi
		log_info "CatalogSource not ready yet, state: $CATALOG_STATE ($i/30)"
		sleep 10
	done

	if [[ "$CATALOG_STATE" != "READY" ]]; then
		log_error "CatalogSource did not become READY within 5 minutes. Checking status..."
		echo ""
		echo "CatalogSource details:"
		oc describe catalogsource compliance-operator -n openshift-marketplace || true
		echo ""
		echo "CatalogSource pod status:"
		oc get pods -n openshift-marketplace -l olm.catalogSource=compliance-operator || true
		echo ""
		echo "Pod logs (if available):"
		oc logs -n openshift-marketplace -l olm.catalogSource=compliance-operator --tail=50 || true
		exit 1
	fi

	log_info "Creating OperatorGroup"
	oc apply -f "$BASE_RAW/config/catalog/operator-group.yaml"

	log_info "Creating Subscription for Community Compliance Operator"
	oc apply -f "$BASE_RAW/config/catalog/subscription.yaml"

	log_info "Patching Subscription with extended bundle unpack timeout (30m)"
	oc patch subscription "$SUBSCRIPTION_NAME" -n "$NAMESPACE" --type merge \
		-p '{"spec":{"config":{"env":[],"bundleUnpackTimeout":"30m"}}}' 2>/dev/null || true
fi

log_info "Waiting for Subscription to populate installedCSV..."
for i in {1..30}; do
	echo "Attempt number $i"
	CSV=$(oc get subscription $SUBSCRIPTION_NAME -n $NAMESPACE -o jsonpath='{.status.installedCSV}' || true)
	if [[ -n "$CSV" ]]; then
		log_info "Found installedCSV: $CSV"
		break
	fi
	log_info "installedCSV not found yet, retrying... ($i/30)"
	sleep 10
done

if [[ -z "$CSV" ]]; then
	log_error "installedCSV was not populated. Exiting."
	exit 1
fi

log_info "Waiting for ClusterServiceVersion ($CSV) to be succeeded..."
for i in {1..30}; do
	PHASE=$(oc get clusterserviceversion "$CSV" -n "$NAMESPACE" -o jsonpath='{.status.phase}' || true)
	log_info "ClusterServiceVersion phase: $PHASE ($i/30)"
	if [[ "$PHASE" == "Succeeded" ]]; then
		log_info "ClusterServiceVersion $CSV is Succeeded."
		break
	fi
	sleep 10
done

if [[ "$PHASE" != "Succeeded" ]]; then
	log_error "ClusterServiceVersion $CSV did not reach Succeeded phase. Exiting."
	exit 1
fi

log_success "Compliance Operator installed successfully."
oc get pods -n $NAMESPACE

# ============================================================================
# RBAC Fix: Ensure compliance-operator can create Jobs
# ============================================================================
# The upstream operator RBAC is missing 'create' permission for Jobs which
# prevents scans from launching. This supplements the missing permissions.
log_info "Applying supplemental RBAC for Job creation..."
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
log_info "✅ Supplemental RBAC applied"

# ============================================================================
# CRD Updates - Ensure CRDs have all required fields
# ============================================================================
# Update ComplianceScan CRD from the same release tag to keep CRD/operator in sync.
# Using 'master' branch CRD can introduce fields the operator binary doesn't recognize.
log_info "Updating ComplianceScan CRD from $CO_REF..."
SCAN_CRD_URL="https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/$CO_REF/config/crd/bases/compliance.openshift.io_compliancescans.yaml"
if oc apply -f "$SCAN_CRD_URL" 2>/dev/null; then
	log_info "✅ ComplianceScan CRD updated from $CO_REF"
else
	log_warn "Could not update ComplianceScan CRD from $CO_REF - scans may get stuck in PENDING"
fi

# ============================================================================
# CustomRule CRD Check and Installation
# ============================================================================
log_info "Checking for CustomRule CRD..."
if ! oc get crd customrules.compliance.openshift.io &>/dev/null; then
	log_warn "CustomRule CRD not found - attempting to install it..."

	# Try to apply from the same ref we're using for the operator
	CRD_URL="$BASE_RAW/deploy/crds/compliance.openshift.io_customrules.yaml"
	log_info "Attempting to apply CustomRule CRD from: $CRD_URL"

	if oc apply -f "$CRD_URL" 2>/dev/null; then
		log_success "✅ CustomRule CRD installed successfully"
	else
		log_warn "Failed to apply from $CRD_URL, trying fallback locations..."

		# Try alternate paths that might exist
		# Note: The correct path is config/crd/bases/ (not deploy/crds/)
		FALLBACK_URLS=(
			"https://raw.githubusercontent.com/$CO_REPO_OWNER/$CO_REPO_NAME/master/config/crd/bases/compliance.openshift.io_customrules.yaml"
			"https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/config/crd/bases/compliance.openshift.io_customrules.yaml"
			"https://raw.githubusercontent.com/openshift/compliance-operator/master/config/crd/bases/compliance.openshift.io_customrules.yaml"
		)

		CRD_APPLIED=false
		for URL in "${FALLBACK_URLS[@]}"; do
			log_info "Trying: $URL"
			if oc apply -f "$URL" 2>/dev/null; then
				log_success "✅ CustomRule CRD installed from fallback location"
				CRD_APPLIED=true
				break
			fi
		done

		if [[ "$CRD_APPLIED" == "false" ]]; then
			log_warn "⚠️  Could not install CustomRule CRD from any known location"
			log_warn "The operator may restart with cache sync errors"
			log_warn "You can manually apply it later with:"
			echo "  oc apply -f https://raw.githubusercontent.com/ComplianceAsCode/compliance-operator/master/deploy/crds/compliance.openshift.io_customrules.yaml"
		fi
	fi

	# Verify the CRD was installed
	if oc get crd customrules.compliance.openshift.io &>/dev/null; then
		log_info "✅ CustomRule CRD is now present"
	fi
else
	log_info "✅ CustomRule CRD already exists"
fi
echo ""

log_info "Waiting up to 5m for non-completed pods in '$NAMESPACE' to be Ready..."
# Clean up any leftover storage probe pods first
oc -n "$NAMESPACE" delete pod -l app=co-storage-probe --ignore-not-found=true >/dev/null 2>&1 || true

for i in {1..30}; do
	# Get current non-completed, non-probe pods
	NSPODS=$(oc -n "$NAMESPACE" get pods \
		-o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null |
		grep -v "co-storage-probe" || true)

	if [[ -z "$NSPODS" ]]; then
		log_info "No non-completed pods found in '$NAMESPACE'"
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
		log_info "All pods in '$NAMESPACE' are Ready"
		break
	fi

	log_info "Waiting for pods to be Ready ($i/30)..."
	sleep 10
done

# Final status check
log_info "Final pod status in '$NAMESPACE':"
oc -n "$NAMESPACE" get pods -o wide 2>/dev/null || true

log_info "Waiting for ProfileBundles to become VALID..."
for i in {1..30}; do
	OCP4_STATUS=$(oc get profilebundle ocp4 -n "$NAMESPACE" -o jsonpath='{.status.dataStreamStatus}' 2>/dev/null || echo "")
	RHCOS4_STATUS=$(oc get profilebundle rhcos4 -n "$NAMESPACE" -o jsonpath='{.status.dataStreamStatus}' 2>/dev/null || echo "")

	if [[ "$OCP4_STATUS" == "VALID" && "$RHCOS4_STATUS" == "VALID" ]]; then
		log_info "All ProfileBundles are VALID"
		break
	fi
	log_info "Waiting for ProfileBundles to be valid ($i/30)... ocp4=$OCP4_STATUS rhcos4=$RHCOS4_STATUS"
	sleep 10
done

log_info "ProfileBundle status:"
oc get profilebundles -n "$NAMESPACE" -o wide 2>/dev/null || true

# ============================================================================
# Pin All Operator Images
# ============================================================================
# Override the 3 RELATED_IMAGE env vars on the operator deployment to use
# our pinned images instead of upstream :latest rolling tags.
log_info "Pinning operator images for reproducible scanning..."
log_info "  RELATED_IMAGE_OPERATOR=$PINNED_OPERATOR_IMAGE"
log_info "  RELATED_IMAGE_OPENSCAP=$PINNED_OPENSCAP_IMAGE"
log_info "  RELATED_IMAGE_PROFILE=$PINNED_CONTENT_IMAGE"

oc set env deployment/compliance-operator -n "$NAMESPACE" \
	RELATED_IMAGE_OPERATOR="$PINNED_OPERATOR_IMAGE" \
	RELATED_IMAGE_OPENSCAP="$PINNED_OPENSCAP_IMAGE" \
	RELATED_IMAGE_PROFILE="$PINNED_CONTENT_IMAGE" 2>/dev/null || log_warn "Could not set image env vars on deployment"

oc patch profilebundle ocp4 -n "$NAMESPACE" --type merge \
	-p "{\"spec\":{\"contentImage\":\"$PINNED_CONTENT_IMAGE\"}}" 2>/dev/null || true
oc patch profilebundle rhcos4 -n "$NAMESPACE" --type merge \
	-p "{\"spec\":{\"contentImage\":\"$PINNED_CONTENT_IMAGE\"}}" 2>/dev/null || true

log_info "Waiting for operator to restart with pinned images..."
oc rollout status deployment/compliance-operator -n "$NAMESPACE" --timeout=120s 2>/dev/null || true

log_info "Waiting for ProfileBundles to re-parse..."
for i in {1..30}; do
	OCP4_STATUS=$(oc get profilebundle ocp4 -n "$NAMESPACE" -o jsonpath='{.status.dataStreamStatus}' 2>/dev/null || echo "")
	RHCOS4_STATUS=$(oc get profilebundle rhcos4 -n "$NAMESPACE" -o jsonpath='{.status.dataStreamStatus}' 2>/dev/null || echo "")
	if [[ "$OCP4_STATUS" == "VALID" && "$RHCOS4_STATUS" == "VALID" ]]; then
		log_info "ProfileBundles re-parsed with pinned content"
		break
	fi
	sleep 10
done
echo ""

# ============================================================================
# Content Image Tracking
# ============================================================================
# Resolve the content image digest and mirror it to quay.io/bapalm with a
# traceable tag so we can reproduce scans with the exact same content later.
log_info "Resolving content image details..."
CONTENT_IMAGE=$(oc get profilebundle ocp4 -n "$NAMESPACE" -o jsonpath='{.spec.contentImage}' 2>/dev/null || echo "")

if [[ -n "$CONTENT_IMAGE" ]] && command -v skopeo &>/dev/null; then
	INSPECT_JSON=$(skopeo inspect --override-arch amd64 --override-os linux "docker://$CONTENT_IMAGE" 2>/dev/null || echo "{}")
	CONTENT_DIGEST=$(echo "$INSPECT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Digest',''))" 2>/dev/null || echo "")
	CONTENT_REVISION=$(echo "$INSPECT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Labels',{}).get('org.opencontainers.image.revision',''))" 2>/dev/null || echo "")

	if [[ -n "$CONTENT_DIGEST" ]]; then
		DIGEST_TAG="${CONTENT_DIGEST#sha256:}"
		DIGEST_TAG="${DIGEST_TAG:0:12}"
		log_info "Content image: $CONTENT_IMAGE"
		log_info "Content digest: $CONTENT_DIGEST"
		if [[ -n "$CONTENT_REVISION" ]]; then
			log_info "Content revision (source commit): $CONTENT_REVISION"
		fi

		MIRROR_CONTENT_IMAGE="quay.io/bapalm/k8scontent:${DIGEST_TAG}"
		log_info "Mirroring content image to $MIRROR_CONTENT_IMAGE for reproducibility..."
		if skopeo copy --all "docker://$CONTENT_IMAGE" "docker://$MIRROR_CONTENT_IMAGE" 2>/dev/null; then
			log_success "Content image mirrored to $MIRROR_CONTENT_IMAGE"
		else
			log_warn "Could not mirror content image (check quay.io/bapalm credentials)"
		fi
	else
		log_warn "Could not resolve content image digest"
	fi
else
	log_warn "Skipping content image tracking (missing skopeo or content image not found)"
fi
echo ""

log_info "Profile parser pods should be using 'restricted-v2' SCC"
log_info "You can verify with: oc get pods -n $NAMESPACE -o custom-columns=NAME:.metadata.name,SCC:.metadata.annotations.'openshift\.io/scc'"

log_info "To schedule a periodic compliance scan, run:"
echo "  ./core/apply-periodic-scan.sh"
