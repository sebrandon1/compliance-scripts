#!/usr/bin/env bash
set -euo pipefail

# Shell smoke test: runs bash -n (syntax check) on all .sh files in the
# project directories that contain automation scripts.

DIRS=(core scripts utilities misc modular)
FAIL=0
PASS=0

for dir in "${DIRS[@]}"; do
	if [[ ! -d "$dir" ]]; then
		continue
	fi

	while IFS= read -r script; do
		if bash -n "$script" 2>&1; then
			echo "PASS: $script"
			PASS=$((PASS + 1))
		else
			echo "FAIL: $script"
			FAIL=$((FAIL + 1))
		fi
	done < <(find "$dir" -name '*.sh' -type f)
done

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
	exit 1
fi
