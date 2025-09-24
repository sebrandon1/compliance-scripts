#!/bin/bash
set -euo pipefail

NAMESPACE="openshift-compliance"
WATCH=false
INTERVAL=10
FILTER=""

usage() {
	echo "Usage: $0 [-n|--namespace NAMESPACE] [--watch] [--interval SECONDS] [--filter SUBSTRING]"
	echo "\nOptions:"
	echo "  -n, --namespace   Target namespace (default: openshift-compliance)"
	echo "      --watch       Continuously watch and refresh output"
	echo "      --interval    Refresh interval in seconds (default: 10)"
	echo "      --filter      Only include scans whose name contains this substring"
	echo "  -h, --help       Show this help"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-n|--namespace)
			NAMESPACE="$2"; shift 2;;
		--watch)
			WATCH=true; shift;;
		--interval)
			INTERVAL="$2"; shift 2;;
		--filter)
			FILTER="$2"; shift 2;;
		-h|--help)
			usage; exit 0;;
		*)
			echo "[ERROR] Unknown argument: $1"; usage; exit 1;;
	esac
done

print_default_sc() {
	local default_sc
	default_sc=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
	if [[ -z "$default_sc" ]]; then
		default_sc=$(oc get sc -o=jsonpath='{range .items[*]}{.metadata.name}:{.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F: '$2=="true"{print $1; exit}' || true)
	fi
	if [[ -n "$default_sc" ]]; then
		echo "Default StorageClass: $default_sc"
	else
		echo "Default StorageClass: (none)"
	fi
}

print_scans() {
	echo "== ComplianceScans ($NAMESPACE) =="
	local scans
	scans=$(oc get compliancescans -n "$NAMESPACE" -o json 2>/dev/null || echo '{}')
	echo "$scans" | jq -r --arg f "$FILTER" '
		(.items // [])
		| map(select($f == "" or (.metadata.name | contains($f))))
		| if length==0 then "(none)" else
			["NAME\tPHASE\tRESULT\tRETRIES\tERROR",
			 (.[] | 
				# Best-effort fields; not all may exist on all versions
				.name as $n
				| (.status.phase // "-") as $p
				| (.status.result // "-") as $r
				| (.status.remainingRetries // .status.scanResult?.remainingRetries // "-") as $retry
				| ( .status.errormsg // ( .status.conditions // [] | map(select(.type=="Failure" or .reason=="Error")) | .[0]?.message ) // "-") as $err
				| ($n+"\t"+$p+"\t"+$r+"\t"+($retry|tostring)+"\t"+($err|tostring))
			)] | .[] end'
}

print_suites() {
	echo "== ComplianceSuites ($NAMESPACE) =="
	oc get compliancesuites -n "$NAMESPACE" -o json 2>/dev/null | jq -r '
		(.items // []) | if length==0 then "(none)" else
		["NAME\tPHASE\tRESULT\tSCAN\tRETRIES\tERROR",
		(.[] as $s | ($s.status.scanStatuses // [])[] | 
			($s.metadata.name) as $suite
			| .name as $scan
			| (.phase // "-") as $phase
			| (.result // "-") as $result
			| (.remainingRetries // "-") as $retry
			| (.errormsg // "-") as $err
			| ($suite+"\t"+$phase+"\t"+$result+"\t"+$scan+"\t"+($retry|tostring)+"\t"+($err|tostring))
		)] | .[] end' || echo "(none)"
}

print_pods() {
	echo "== Pods ($NAMESPACE) =="
	oc get pods -n "$NAMESPACE" -o wide || true
}

print_pvcs() {
	echo "== PVCs ($NAMESPACE) =="
	oc get pvc -n "$NAMESPACE" -o wide || true
}

print_profilebundles() {
	echo "== ProfileBundles ($NAMESPACE) =="
	oc get profilebundles -n "$NAMESPACE" -o json 2>/dev/null | jq -r '
		(.items // []) | if length==0 then "(none)" else
		["NAME\tREADY\tSTATUS",
		(.[] | .metadata.name as $n | (.status.conditions // []) | 
			(map(select(.type=="Ready")[0]) | .[0]) as $c |
			($n+"\t"+($c.status // "-")+"\t"+($c.message // "-")))
		] | .[] end' || echo "(none)"
}

print_events() {
	echo "== Recent Events ($NAMESPACE) =="
	oc get events -n "$NAMESPACE" --sort-by=.lastTimestamp 2>/dev/null | tail -n 30 || true
}

render() {
	date
	print_default_sc
	echo
	print_scans
	echo
	print_suites
	echo
	print_pods
	echo
	print_pvcs
	echo
	print_profilebundles
	echo
	print_events
}

if [[ "$WATCH" == true ]]; then
	while true; do
		clear || true
		render || true
		sleep "$INTERVAL"
	done
else
	render
fi




