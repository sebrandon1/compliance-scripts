#!/bin/bash
set -euo pipefail

show_usage() {
	echo "Usage: $0 --pull-secret /path/to/pull-secret.json [--kubeconfig /path/to/kubeconfig] [--mode merge|replace]" >&2
	echo "Optional: --namespace openshift-config --secret-name pull-secret --no-verify" >&2
}

KUBECONFIG_ARG=""
PULL_SECRET_FILE=""
MODE="merge" # merge|replace
NAMESPACE="openshift-config"
SECRET_NAME="pull-secret"
VERIFY=true

while [[ $# -gt 0 ]]; do
	case "$1" in
	--kubeconfig)
		KUBECONFIG_ARG="$2"
		shift 2
		;;
	--pull-secret)
		PULL_SECRET_FILE="$2"
		shift 2
		;;
	--mode)
		MODE="$2"
		shift 2
		;;
	--namespace)
		NAMESPACE="$2"
		shift 2
		;;
	--secret-name)
		SECRET_NAME="$2"
		shift 2
		;;
	--no-verify)
		VERIFY=false
		shift
		;;
	-h | --help)
		show_usage
		exit 0
		;;
	*)
		echo "Unknown argument: $1" >&2
		show_usage
		exit 1
		;;
	esac
done

if [[ -n "$KUBECONFIG_ARG" ]]; then
	export KUBECONFIG="$KUBECONFIG_ARG"
fi

if ! command -v oc >/dev/null 2>&1; then
	echo "[ERROR] oc CLI not found in PATH." >&2
	exit 1
fi

if [[ -z "$PULL_SECRET_FILE" ]]; then
	echo "[ERROR] --pull-secret is required" >&2
	show_usage
	exit 1
fi

if [[ ! -s "$PULL_SECRET_FILE" ]]; then
	echo "[ERROR] Provided pull-secret file not found or empty: $PULL_SECRET_FILE" >&2
	exit 1
fi

if [[ "$MODE" != "merge" && "$MODE" != "replace" ]]; then
	echo "[ERROR] --mode must be 'merge' or 'replace'" >&2
	exit 1
fi

# Verify cluster access early
if ! oc whoami >/dev/null 2>&1; then
	echo "[ERROR] Cannot access cluster with current kubeconfig. Set --kubeconfig or KUBECONFIG." >&2
	exit 1
fi

TS=$(date +%Y%m%d%H%M%S)
TMPDIR=$(mktemp -d "/tmp/psecret.XXXXXX")
trap 'rm -rf "$TMPDIR"' EXIT

BACKUP="/tmp/${SECRET_NAME}-backup-${TS}.json"

echo "[INFO] Backing up existing secret '$SECRET_NAME' from namespace '$NAMESPACE' to $BACKUP"
oc extract "secret/${SECRET_NAME}" -n "$NAMESPACE" --to="$TMPDIR" >/dev/null
cp "$TMPDIR/.dockerconfigjson" "$BACKUP"

SOURCE_FOR_UPDATE="$PULL_SECRET_FILE"

if [[ "$MODE" == "merge" ]]; then
	if ! command -v python3 >/dev/null 2>&1; then
		echo "[ERROR] python3 is required for merge mode. Install python3 or use --mode replace." >&2
		exit 1
	fi
	CURRENT_JSON="$TMPDIR/current.json"
	MERGED_JSON="$TMPDIR/merged.json"
	cp "$BACKUP" "$CURRENT_JSON"

	cat >"$TMPDIR/merge_pull_secret.py" <<'PY'
import json, sys

cur_path, new_path, out_path = sys.argv[1:4]
with open(cur_path) as f:
	a = json.load(f)
with open(new_path) as f:
	b = json.load(f)

a.setdefault("auths", {}).update(b.get("auths", {}))
with open(out_path, "w") as f:
	json.dump(a, f)
PY

	echo "[INFO] Merging new credentials into existing secret data"
	python3 "$TMPDIR/merge_pull_secret.py" "$CURRENT_JSON" "$PULL_SECRET_FILE" "$MERGED_JSON"
	SOURCE_FOR_UPDATE="$MERGED_JSON"
fi

echo "[INFO] Updating cluster secret '$SECRET_NAME' in namespace '$NAMESPACE'"
oc set data "secret/${SECRET_NAME}" -n "$NAMESPACE" --from-file=.dockerconfigjson="$SOURCE_FOR_UPDATE" >/dev/null
oc -n "$NAMESPACE" patch "secret/${SECRET_NAME}" --type merge -p '{"type":"kubernetes.io/dockerconfigjson"}' >/dev/null || true

if [[ "$VERIFY" == true ]]; then
	VERIFYDIR=$(mktemp -d "/tmp/psecretv.XXXXXX")
	trap 'rm -rf "$TMPDIR" "$VERIFYDIR"' EXIT
	oc extract "secret/${SECRET_NAME}" -n "$NAMESPACE" --to="$VERIFYDIR" >/dev/null
	echo "[INFO] Registries in updated secret:"
	if command -v python3 >/dev/null 2>&1; then
		python3 - "$VERIFYDIR/.dockerconfigjson" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
	data = json.load(f)
print("\n".join(sorted(data.get("auths", {}).keys())))
PY
	else
		# Fallback: try to parse roughly with sed/grep if python3 missing
		sed -n '/"auths"[[:space:]]*:/,/}/p' "$VERIFYDIR/.dockerconfigjson" | grep '"' | grep ':' | grep -v auths | cut -d '"' -f2 | sort -u || true
	fi
fi

echo "[DONE] Updated '$SECRET_NAME'. Backup at $BACKUP"
