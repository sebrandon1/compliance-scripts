# RHCOS Static Scan Baselines

Expected FAIL results per RHCOS version, generated from `scripts/rhcos-static-scan.sh`.

Each file lists the check names expected to FAIL on that RHCOS version with the
pinned content image (`k8scontent:v0.1.80`). One check name per line.

To regenerate a baseline:
```bash
make rhcos-static-scan OCP_VERSION=4.21
# Then copy the FAILs from the results
python3 scripts/parse-oscap-results.py /tmp/rhcos-scan-results/results-e8.xml --failing-only --format text | \
  sed 's/  FAIL: //' | sort > tests/rhcos-baselines/rhcos-4.21-e8-expected-fails.txt
```
