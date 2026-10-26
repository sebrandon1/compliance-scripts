#!/usr/bin/env python3
"""Behavioral tests for scripts/verify-all-groups.sh (issue #421).

The script talks to the cluster through `oc` and to GitHub through `curl`; both
are stubbed so these tests never touch the network or a live cluster.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts" / "verify-all-groups.sh"
TRACKING = REPO / "docs" / "_data" / "tracking.json"

OC_STUB = """#!/bin/sh
case "$*" in
  whoami*) echo 'system:admin' ;;
  *version*) echo '{"openshiftVersion": "0.0.0"}' ;;
  get\\ compliancecheckresult*) echo '{"items": []}' ;;
  *) echo '' ;;
esac
exit 0
"""

# Answers the API listing and raw-file downloads. CURL_STATUS selects the HTTP
# status the fake GitHub API returns for the contents endpoint; CURL_ARGS_LOG
# records each invocation so tests can assert on the arguments.
CURL_STUB = """#!/bin/sh
[ -n "${CURL_ARGS_LOG:-}" ] && printf '%s\\n' "$*" >> "$CURL_ARGS_LOG"
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -w) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  *raw.githubusercontent.com*)
    printf 'apiVersion: machineconfiguration.openshift.io/v1\\nkind: MachineConfig\\nmetadata:\\n  name: stub\\n' > "$out"
    exit 0 ;;
esac
status="${CURL_STATUS:-200}"
case "$status" in
  200) body='[{"name":"75-stub-hardening.yaml"}]' ;;
  403) body='{"message":"API rate limit exceeded for 1.2.3.4."}' ;;
  404) body='{"message":"Not Found"}' ;;
  *) body='{"message":"Server Error"}' ;;
esac
if [ -n "$out" ]; then
  printf '%s' "$body" > "$out"
else
  printf '%s' "$body"
fi
printf '\\n%s' "$status"
exit 0
"""


@pytest.fixture(scope="module")
def group_with_compare() -> str:
    """Any tracked group with a compare branch, so the fetch path is exercised."""
    groups = json.loads(TRACKING.read_text())["groups"]
    return next(name for name, meta in groups.items() if meta.get("compare"))


def _run(stub_binary, run_script, tmp_path, group, status: str, **env):
    stub_binary("oc", OC_STUB)
    stub_binary("yq", "#!/bin/sh\nexit 0\n")
    stub_binary("curl", CURL_STUB)
    return run_script(
        SCRIPT,
        "--groups", group,
        "--output-dir", tmp_path / "out",
        "--dry-run",
        env={"CURL_STATUS": status, **env},
    )


def test_rate_limit_fails_loudly(stub_binary, run_script, tmp_path, group_with_compare):
    result = _run(stub_binary, run_script, tmp_path, group_with_compare, "403")
    output = result.stdout + result.stderr
    assert result.returncode == 1, output
    assert "rate limit" in output.lower()
    assert "GH_TOKEN" in output


def test_api_outage_fails_loudly(stub_binary, run_script, tmp_path, group_with_compare):
    result = _run(stub_binary, run_script, tmp_path, group_with_compare, "500")
    output = result.stdout + result.stderr
    assert result.returncode == 1, output
    assert "Aborting" in output


def test_gh_token_is_sent_as_bearer_header(stub_binary, run_script, tmp_path, group_with_compare):
    args_log = tmp_path / "curl-args"
    result = _run(stub_binary, run_script, tmp_path, group_with_compare, "200",
                  GH_TOKEN="test-token", CURL_ARGS_LOG=str(args_log))
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Authorization: Bearer test-token" in args_log.read_text()


def test_dry_run_saves_machineconfigs(stub_binary, run_script, tmp_path, group_with_compare):
    result = _run(stub_binary, run_script, tmp_path, group_with_compare, "200")
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    saved = tmp_path / "out" / "machineconfigs" / group_with_compare / "75-stub-hardening.yaml"
    assert saved.is_file(), output
    assert "Dry run complete" in output


def test_missing_branch_skips_group(stub_binary, run_script, tmp_path, group_with_compare):
    result = _run(stub_binary, run_script, tmp_path, group_with_compare, "404")
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "no MC files found" in output
    assert "rate limit" not in output.lower()
