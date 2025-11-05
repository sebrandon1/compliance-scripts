#!/bin/bash
set -euo pipefail

# Deploy a DaemonSet that provisions a file-backed loop device on every node
# and optionally patch LVMS (LVMCluster) to use it via deviceSelector.paths.

NAMESPACE="openshift-storage"
LOOP_DEVICE="/dev/loop0"
FILE_SIZE_GIB=10
BACKING_FILE_NAME="loopback.img"
PATCH_LVMS=true
WAIT_TIMEOUT="300s"
AUTO_DETECT_DEVICE=true

usage() {
	cat <<USAGE
Usage: $(basename "$0") [options]

Deploy a privileged DaemonSet that sets up a loop device on each node.
Also patch LVMS LVMCluster to use the loop device in deviceSelector.paths.

Options:
  --namespace <ns>     Namespace to deploy resources (default: ${NAMESPACE})
  --device <path>      Loop device path to target (default: ${LOOP_DEVICE})
  --size-gib <num>     Backing file size in GiB (default: ${FILE_SIZE_GIB})
  --skip-patch         Do not patch LVMCluster after deploying the DaemonSet
  --no-auto-detect     Do not auto-detect loop device; use --device as-is
  --wait-timeout <t>   Rollout wait timeout (default: ${WAIT_TIMEOUT})
  -h, --help           Show this help and exit

Notes:
  - Requires cluster-admin to bind the 'privileged' SCC to the ServiceAccount.
  - The backing file is created at /var/lib/loopback/${BACKING_FILE_NAME} on each node.
  - If ${LOOP_DEVICE} is already taken, the container will attempt the first free loop device.
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--namespace)
		NAMESPACE="$2"
		shift 2
		;;
	--device)
		LOOP_DEVICE="$2"
		shift 2
		;;
	--size-gib)
		FILE_SIZE_GIB="$2"
		shift 2
		;;
	--skip-patch)
		PATCH_LVMS=false
		shift
		;;
	--no-auto-detect)
		AUTO_DETECT_DEVICE=false
		shift
		;;
	--wait-timeout)
		WAIT_TIMEOUT="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "[WARN] Ignoring unknown argument: $1"
		shift
		;;
	esac
done

if ! command -v oc >/dev/null 2>&1; then
	echo "[ERROR] 'oc' CLI not found in PATH. Please install OpenShift CLI." >&2
	exit 1
fi

echo "[INFO] Using KUBECONFIG: ${KUBECONFIG:-<default>}"
SERVER=$(oc whoami --show-server 2>/dev/null || true)
CONTEXT=$(oc config current-context 2>/dev/null || true)
echo "[INFO] Cluster API server: ${SERVER:-unknown} (context: ${CONTEXT:-unknown})"

echo "[INFO] Ensuring namespace '$NAMESPACE' exists"
oc get ns "$NAMESPACE" >/dev/null 2>&1 || oc create ns "$NAMESPACE"

echo "[INFO] Creating ServiceAccount 'loopback-setup' in '$NAMESPACE'"
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: loopback-setup
  namespace: ${NAMESPACE}
EOF

echo "[INFO] Binding 'privileged' SCC to ServiceAccount 'loopback-setup'"
oc adm policy add-scc-to-user privileged -n "$NAMESPACE" -z loopback-setup >/dev/null

BACKING_FILE_HOST_PATH="/var/lib/loopback/${BACKING_FILE_NAME}"
BACKING_FILE_POD_PATH="/host-var-lib-loopback/${BACKING_FILE_NAME}"

echo "[INFO] Applying DaemonSet 'loopback-setup' in namespace '$NAMESPACE'"
echo "[INFO] Checking for existing DaemonSet 'loopback-setup' in '$NAMESPACE'"
if oc -n "$NAMESPACE" get ds/loopback-setup >/dev/null 2>&1; then
	echo "[INFO] Deleting existing DaemonSet 'loopback-setup' before re-deploying"
	oc -n "$NAMESPACE" delete ds/loopback-setup --ignore-not-found || true
	if ! oc -n "$NAMESPACE" wait --for=delete ds/loopback-setup --timeout="$WAIT_TIMEOUT"; then
		echo "[WARN] Wait for DaemonSet deletion returned non-zero; continuing"
	fi
fi
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: loopback-setup
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels:
      app: loopback-setup
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: loopback-setup
    spec:
      serviceAccountName: loopback-setup
      hostPID: true
      tolerations:
      - operator: Exists
      containers:
      - name: setup
        image: registry.access.redhat.com/ubi9/ubi
        imagePullPolicy: IfNotPresent
        securityContext:
          privileged: true
        env:
        - name: LOOP_DEVICE
          value: "${LOOP_DEVICE}"
        - name: FILE_SIZE_GIB
          value: "${FILE_SIZE_GIB}"
        - name: BACKING_FILE
          value: "${BACKING_FILE_POD_PATH}"
        command: ["/bin/bash","-ceu","--"]
        args:
        - |
          set -euo pipefail
          echo "[INFO] Preparing loop device: \"\${LOOP_DEVICE}\" with backing file: \"\${BACKING_FILE}\" (\${FILE_SIZE_GIB}GiB)"
          mkdir -p "/\$(dirname \"\${BACKING_FILE#/*}\")"
          if [ ! -f "\${BACKING_FILE}" ]; then
            echo "[INFO] Creating sparse backing file \${BACKING_FILE}"
            dd if=/dev/zero of="\${BACKING_FILE}" bs=1M count=0 seek="\$((FILE_SIZE_GIB*1024))"
          else
            echo "[INFO] Backing file already exists: \${BACKING_FILE}"
          fi
          echo "[INFO] Ensuring loop kernel module is present (best-effort)"
          modprobe loop || true
          # Attach to the requested device only if it isn't already bound to a different file.
          # If the requested device exists but is not our file, use the first free device.
          if losetup -a | grep -q "^\${LOOP_DEVICE}: .* (\${BACKING_FILE})$"; then
            echo "[INFO] \${LOOP_DEVICE} already configured for our backing file; leaving as-is"
          else
            if losetup -a | grep -q "^\${LOOP_DEVICE}:"; then
              FREE_DEV=\$(losetup -f)
              losetup "\${FREE_DEV}" "\${BACKING_FILE}"
              echo "[INFO] \${LOOP_DEVICE} was in use; attached \${BACKING_FILE} to \${FREE_DEV} instead"
            else
              if losetup "\${LOOP_DEVICE}" "\${BACKING_FILE}" 2>/dev/null; then
                echo "[INFO] Attached \${BACKING_FILE} to \${LOOP_DEVICE}"
              else
                FREE_DEV=\$(losetup -f)
                losetup "\${FREE_DEV}" "\${BACKING_FILE}"
                echo "[INFO] Could not attach to \${LOOP_DEVICE}; attached to \${FREE_DEV} instead"
              fi
            fi
          fi
          echo "[READY] Loop devices:"
          losetup -a || true
          # Keep container alive so the loop device persists
          sleep infinity
        volumeMounts:
        - name: dev
          mountPath: /dev
        - name: modules
          mountPath: /lib/modules
          readOnly: true
        - name: var-lib-loopback
          mountPath: /host-var-lib-loopback
      volumes:
      - name: dev
        hostPath:
          path: /dev
      - name: modules
        hostPath:
          path: /lib/modules
      - name: var-lib-loopback
        hostPath:
          path: /var/lib/loopback
EOF

echo "[INFO] Waiting for DaemonSet rollout to complete (timeout: ${WAIT_TIMEOUT})"
if ! oc -n "$NAMESPACE" rollout status ds/loopback-setup --timeout="$WAIT_TIMEOUT"; then
	echo "[ERROR] DaemonSet 'loopback-setup' did not finish rollout successfully within ${WAIT_TIMEOUT}" >&2
	exit 1
fi

DETECTED_DEVICE=""
if [[ "$AUTO_DETECT_DEVICE" == true ]]; then
	echo "[INFO] Attempting to auto-detect loop device attached to ${BACKING_FILE_POD_PATH}"
	PODS=$(oc -n "$NAMESPACE" get pods -l app=loopback-setup -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
	if [[ -n "$PODS" ]]; then
		CMD="losetup -a | grep -F \"(${BACKING_FILE_POD_PATH})\" | head -n1 | cut -d: -f1 || true"
		while read -r POD; do
			[[ -z "$POD" ]] && continue
			DEV=$(oc -n "$NAMESPACE" exec "$POD" -- bash -ceu -- "$CMD" 2>/dev/null | tr -d '\r')
			if [[ -n "$DEV" ]]; then
				DETECTED_DEVICE="$DEV"
				break
			fi
		done <<<"$PODS"
	fi
	if [[ -n "$DETECTED_DEVICE" ]]; then
		echo "[INFO] Detected loop device for our backing file: $DETECTED_DEVICE"
		LOOP_DEVICE="$DETECTED_DEVICE"
	else
		echo "[WARN] Could not auto-detect loop device for ${BACKING_FILE_POD_PATH}; using requested ${LOOP_DEVICE}"
	fi
fi

if [[ "$PATCH_LVMS" == true ]]; then
	echo "[INFO] Attempting to patch LVMCluster deviceSelector.paths with ${LOOP_DEVICE}"
	# Find existing LVMCluster(s)
	LVM_LIST=$(oc get lvmcluster -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}' 2>/dev/null || true)
	if [[ -z "$LVM_LIST" ]]; then
		echo "[WARN] No LVMCluster found. Skipping patch. Install LVMS and re-run if needed."
	else
		while read -r LNS LNAME; do
			[[ -z "${LNS:-}" || -z "${LNAME:-}" ]] && continue
			echo "[INFO] Patching LVMCluster '${LNAME}' in namespace '${LNS}'"
			# Fetch current deviceClasses to decide idempotent action
			LC_JSON=$(oc -n "$LNS" get lvmcluster "$LNAME" -o json 2>/dev/null || true)
			DC_JSON=$(echo "$LC_JSON" | jq -c '.spec.storage.deviceClasses // []' 2>/dev/null || echo '[]')
			if echo "$DC_JSON" | jq -e ".[] | select(.deviceSelector.paths != null) | .deviceSelector.paths[] | select(. == \"${LOOP_DEVICE}\")" >/dev/null; then
				echo "[INFO] LVMCluster already references ${LOOP_DEVICE}; skipping patch"
			elif echo "$DC_JSON" | jq -e 'length == 0' >/dev/null; then
				echo "[INFO] Setting initial deviceClasses with ${LOOP_DEVICE}"
				PATCH_PAYLOAD_MERGE='{"spec":{"storage":{"deviceClasses":[{"name":"loopback","deviceSelector":{"paths":["'"${LOOP_DEVICE}"'"]}}]}}}'
				if oc -n "$LNS" patch lvmcluster "$LNAME" --type=merge -p "$PATCH_PAYLOAD_MERGE"; then
					echo "[SUCCESS] Initialized deviceClasses with ${LOOP_DEVICE}"
				else
					echo "[ERROR] Failed to initialize deviceClasses; manual intervention may be required."
				fi
			else
				echo "[WARN] Existing deviceClasses present and do not include ${LOOP_DEVICE}. Skipping patch to avoid webhook violations."
				echo "[HINT] Create or edit the LVMCluster up-front with desired deviceClasses, or reinstall LVMS with a spec that includes deviceSelector.paths."
			fi
		done <<<"$LVM_LIST"
	fi
fi

echo "[DONE] Loopback DaemonSet deployed in namespace '${NAMESPACE}'."
echo "[INFO] To verify devices: oc -n ${NAMESPACE} logs -l app=loopback-setup --tail=50"
echo "[INFO] If LVMS was patched, reconcile may take a few minutes."
