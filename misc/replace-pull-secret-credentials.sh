#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

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

require_cmd oc

if [[ -z "$PULL_SECRET_FILE" ]]; then
	log_error "--pull-secret is required"
	show_usage
	exit 1
fi

if [[ ! -s "$PULL_SECRET_FILE" ]]; then
	log_error "Provided pull-secret file not found or empty: $PULL_SECRET_FILE"
	exit 1
fi

if [[ "$MODE" != "merge" && "$MODE" != "replace" ]]; then
	log_error "--mode must be 'merge' or 'replace'"
	exit 1
fi

require_cluster

TS=$(date +%Y%m%d%H%M%S)
TMPDIR=$(mktemp -d "/tmp/psecret.XXXXXX")
trap 'rm -rf "$TMPDIR"' EXIT

BACKUP="/tmp/${SECRET_NAME}-backup-${TS}.json"

log_info "Backing up existing secret '$SECRET_NAME' from namespace '$NAMESPACE' to $BACKUP"
oc extract "secret/${SECRET_NAME}" -n "$NAMESPACE" --to="$TMPDIR" >/dev/null
cp "$TMPDIR/.dockerconfigjson" "$BACKUP"

SOURCE_FOR_UPDATE="$PULL_SECRET_FILE"

if [[ "$MODE" == "merge" ]]; then
	require_cmd python3
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

	log_info "Merging new credentials into existing secret data"
	python3 "$TMPDIR/merge_pull_secret.py" "$CURRENT_JSON" "$PULL_SECRET_FILE" "$MERGED_JSON"
	SOURCE_FOR_UPDATE="$MERGED_JSON"
fi

log_info "Updating cluster secret '$SECRET_NAME' in namespace '$NAMESPACE'"
oc set data "secret/${SECRET_NAME}" -n "$NAMESPACE" --from-file=.dockerconfigjson="$SOURCE_FOR_UPDATE" >/dev/null
oc -n "$NAMESPACE" patch "secret/${SECRET_NAME}" --type merge -p '{"type":"kubernetes.io/dockerconfigjson"}' >/dev/null || true

if [[ "$VERIFY" == true ]]; then
	VERIFYDIR=$(mktemp -d "/tmp/psecretv.XXXXXX")
	trap 'rm -rf "$TMPDIR" "$VERIFYDIR"' EXIT
	oc extract "secret/${SECRET_NAME}" -n "$NAMESPACE" --to="$VERIFYDIR" >/dev/null
	log_info "Registries in updated secret:"
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
