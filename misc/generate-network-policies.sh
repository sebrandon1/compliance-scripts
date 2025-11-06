#!/bin/bash
set -euo pipefail

usage() {
	echo "Usage: $0 [--apply] [--out-dir DIR] [--exclude-regex REGEX] [--namespaces ns1,ns2]"
	echo "\nOptions:"
	echo "  --apply             Apply NetworkPolicies to the cluster (default: preview only)"
	echo "  --out-dir DIR       When not applying, write YAMLs to DIR (default: ./generated-networkpolicies)"
	echo "  --exclude-regex R   Regex of namespaces to skip (default: '^(openshift-|kube-|default|operators|redhat-operators)$')"
	echo "  --namespaces LIST   Comma-separated explicit namespaces to target (overrides discovery)"
	echo "  -h, --help          Show this help message"
}

if ! command -v oc >/dev/null 2>&1; then
	echo "[ERROR] 'oc' CLI is required. Please install and login to your cluster."
	exit 1
fi

if ! oc whoami >/dev/null 2>&1; then
	echo "[ERROR] Unable to connect to the cluster. Please run 'oc login' and retry."
	exit 1
fi

APPLY=0
OUT_DIR="generated-networkpolicies"
EXCLUDE_REGEX='^(openshift-|kube-|default|operators|redhat-operators)$'
EXPLICIT_NAMESPACES=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--apply)
		APPLY=1
		shift
		;;
	--out-dir)
		OUT_DIR="$2"
		shift 2
		;;
	--exclude-regex)
		EXCLUDE_REGEX="$2"
		shift 2
		;;
	--namespaces)
		EXPLICIT_NAMESPACES="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "[ERROR] Unknown option: $1"
		usage
		exit 1
		;;
	esac
done

if [[ $APPLY -eq 0 ]]; then
	mkdir -p "$OUT_DIR"
fi

# Determine target namespaces
namespaces=()
if [[ -n "$EXPLICIT_NAMESPACES" ]]; then
	IFS=',' read -r -a namespaces <<<"$EXPLICIT_NAMESPACES"
else
	while IFS= read -r ns; do
		[[ -z "$ns" ]] && continue
		if [[ "$ns" =~ $EXCLUDE_REGEX ]]; then
			continue
		fi
		namespaces+=("$ns")
	done < <(oc get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
fi

created=0
skipped_present=0
processed=0

for ns in "${namespaces[@]}"; do
	processed=$((processed + 1))
	# Skip if a default-deny policy already exists (by name)
	if oc -n "$ns" get networkpolicy default-deny-all >/dev/null 2>&1; then
		skipped_present=$((skipped_present + 1))
		echo "[SKIP] $ns already has NetworkPolicy/default-deny-all"
		continue
	fi

	# YAML content for default deny ingress+egress
	yaml=$(
		cat <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
EOF
	)

	if [[ $APPLY -eq 1 ]]; then
		echo "[APPLY] Creating NetworkPolicy/default-deny-all in namespace $ns"
		echo "$yaml" | oc -n "$ns" apply -f -
		created=$((created + 1))
	else
		file="$OUT_DIR/${ns}-default-deny-all.yaml"
		echo "$yaml" >"$file"
		echo "[WRITE] $file"
		created=$((created + 1))
	fi
done

echo "[SUMMARY] namespaces_processed=$processed, created=$created, skipped_present=$skipped_present, apply=$APPLY"
