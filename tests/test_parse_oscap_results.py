#!/usr/bin/env python3
"""Tests for scripts/parse-oscap-results.py"""

import json
import os
import sys
import tempfile
import shutil

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location(
    "parse_oscap",
    os.path.join(os.path.dirname(__file__), '..', 'scripts',
                 'parse-oscap-results.py'))
parse_oscap = module_from_spec(spec)
spec.loader.exec_module(parse_oscap)

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), 'fixtures')
SAMPLE_XML = os.path.join(FIXTURES_DIR, 'sample-oscap-results.xml')


@pytest.fixture
def tmpdir():
    d = tempfile.mkdtemp()
    yield d
    shutil.rmtree(d)


def write_xml(directory, filename, content):
    """Write an XML file into a directory and return the path."""
    filepath = os.path.join(directory, filename)
    with open(filepath, 'w') as f:
        f.write(content)
    return filepath


def write_json_file(directory, filename, data):
    """Write a JSON file and return the path."""
    filepath = os.path.join(directory, filename)
    with open(filepath, 'w') as f:
        json.dump(data, f)
    return filepath


MINIMAL_XML = """\
<?xml version="1.0" encoding="UTF-8"?>
<Benchmark xmlns="http://checklists.nist.gov/xccdf/1.2">
  <TestResult>
    <rule-result idref="xccdf_org.ssgproject.content_rule_test_check">
      <result>pass</result>
    </rule-result>
  </TestResult>
</Benchmark>
"""

MULTI_RESULT_XML = """\
<?xml version="1.0" encoding="UTF-8"?>
<Benchmark xmlns="http://checklists.nist.gov/xccdf/1.2">
  <TestResult>
    <rule-result idref="xccdf_org.ssgproject.content_rule_check_pass">
      <result>pass</result>
    </rule-result>
    <rule-result idref="xccdf_org.ssgproject.content_rule_check_fail">
      <result>fail</result>
    </rule-result>
    <rule-result idref="xccdf_org.ssgproject.content_rule_check_notapplicable">
      <result>notapplicable</result>
    </rule-result>
  </TestResult>
</Benchmark>
"""

EMPTY_XML = """\
<?xml version="1.0" encoding="UTF-8"?>
<Benchmark xmlns="http://checklists.nist.gov/xccdf/1.2">
  <TestResult>
  </TestResult>
</Benchmark>
"""

NO_RESULT_ELEM_XML = """\
<?xml version="1.0" encoding="UTF-8"?>
<Benchmark xmlns="http://checklists.nist.gov/xccdf/1.2">
  <TestResult>
    <rule-result idref="xccdf_org.ssgproject.content_rule_missing_result">
    </rule-result>
  </TestResult>
</Benchmark>
"""


# --- parse_results ---


class TestParseResults:
    def test_sample_fixture_file(self):
        checks = parse_oscap.parse_results(SAMPLE_XML)
        assert len(checks) == 5
        names = [c["name"] for c in checks]
        assert "no-empty-passwords" in names
        assert "sshd-disable-root-login" in names
        assert "configure-crypto-policy" in names

    def test_result_values(self):
        checks = parse_oscap.parse_results(SAMPLE_XML)
        by_name = {c["name"]: c for c in checks}
        assert by_name["no-empty-passwords"]["result"] == "pass"
        assert by_name["sshd-disable-root-login"]["result"] == "fail"
        assert by_name["sshd-set-idle-timeout"]["result"] == "notapplicable"

    def test_id_preserved(self):
        checks = parse_oscap.parse_results(SAMPLE_XML)
        ids = [c["id"] for c in checks]
        assert "xccdf_org.ssgproject.content_rule_no_empty_passwords" in ids

    def test_name_transformation(self):
        checks = parse_oscap.parse_results(SAMPLE_XML)
        by_id = {c["id"]: c for c in checks}
        rule_id = "xccdf_org.ssgproject.content_rule_audit_rules_dac_modification"
        assert by_id[rule_id]["name"] == "audit-rules-dac-modification"

    def test_minimal_xml(self, tmpdir):
        fp = write_xml(tmpdir, "minimal.xml", MINIMAL_XML)
        checks = parse_oscap.parse_results(fp)
        assert len(checks) == 1
        assert checks[0]["name"] == "test-check"
        assert checks[0]["result"] == "pass"

    def test_empty_results(self, tmpdir):
        fp = write_xml(tmpdir, "empty.xml", EMPTY_XML)
        checks = parse_oscap.parse_results(fp)
        assert checks == []

    def test_missing_result_element(self, tmpdir):
        fp = write_xml(tmpdir, "no-result.xml", NO_RESULT_ELEM_XML)
        checks = parse_oscap.parse_results(fp)
        assert len(checks) == 1
        assert checks[0]["result"] == "unknown"

    def test_multiple_result_types(self, tmpdir):
        fp = write_xml(tmpdir, "multi.xml", MULTI_RESULT_XML)
        checks = parse_oscap.parse_results(fp)
        assert len(checks) == 3
        results = {c["name"]: c["result"] for c in checks}
        assert results["check-pass"] == "pass"
        assert results["check-fail"] == "fail"
        assert results["check-notapplicable"] == "notapplicable"


# --- count_results ---


class TestCountResults:
    def test_counts_by_status(self):
        checks = [
            {"result": "pass"},
            {"result": "pass"},
            {"result": "fail"},
            {"result": "notapplicable"},
        ]
        counts = parse_oscap.count_results(checks)
        assert counts["pass"] == 2
        assert counts["fail"] == 1
        assert counts["notapplicable"] == 1

    def test_empty_list(self):
        counts = parse_oscap.count_results([])
        assert counts == {}

    def test_single_status(self):
        checks = [{"result": "pass"}, {"result": "pass"}]
        counts = parse_oscap.count_results(checks)
        assert counts == {"pass": 2}


# --- sort_group_key ---


class TestSortGroupKey:
    def test_ordering(self):
        groups = ["M1", "H2", "L1", "MAN3", "H1", "M10"]
        result = sorted(groups, key=parse_oscap.sort_group_key)
        assert result == ["H1", "H2", "L1", "M1", "M10", "MAN3"]

    def test_unknown_prefix(self):
        key = parse_oscap.sort_group_key("X5")
        assert key == (99, 5)

    def test_no_number(self):
        key = parse_oscap.sort_group_key("H")
        assert key == (0, 0)


# --- load_tracking ---


class TestLoadTracking:
    def test_loads_mapping(self, tmpdir):
        tracking = {
            "groups": {
                "H1": {
                    "title": "Crypto", "severity": "HIGH",
                    "priority": 1, "status": "pass", "platform": "rhcos",
                },
            },
            "remediations": {
                "crypto-policy": {"group": "H1"},
                "empty-passwords": {"group": "H1"},
            },
        }
        fp = write_json_file(tmpdir, "tracking.json", tracking)
        check_to_group, groups = parse_oscap.load_tracking(fp)
        assert check_to_group["crypto-policy"] == "H1"
        assert check_to_group["empty-passwords"] == "H1"
        assert "H1" in groups

    def test_empty_tracking(self, tmpdir):
        fp = write_json_file(tmpdir, "tracking.json",
                             {"groups": {}, "remediations": {}})
        check_to_group, groups = parse_oscap.load_tracking(fp)
        assert check_to_group == {}
        assert groups == {}


# --- build_group_results ---


class TestBuildGroupResults:
    def test_aggregates_by_group(self):
        checks = [
            {"name": "check-a", "result": "pass"},
            {"name": "check-b", "result": "fail"},
            {"name": "check-c", "result": "pass"},
        ]
        check_to_group = {
            "check-a": "H1",
            "check-b": "H1",
            "check-c": "M1",
        }
        result = parse_oscap.build_group_results(checks, check_to_group)
        assert result["H1"]["pass"] == 1
        assert result["H1"]["fail"] == 1
        assert result["M1"]["pass"] == 1
        assert result["M1"]["fail"] == 0

    def test_unmapped_checks_excluded(self):
        checks = [
            {"name": "mapped", "result": "pass"},
            {"name": "unmapped", "result": "fail"},
        ]
        check_to_group = {"mapped": "H1"}
        result = parse_oscap.build_group_results(checks, check_to_group)
        assert len(result) == 1
        assert "H1" in result

    def test_other_status(self):
        checks = [{"name": "check-a", "result": "notapplicable"}]
        check_to_group = {"check-a": "H1"}
        result = parse_oscap.build_group_results(checks, check_to_group)
        assert result["H1"]["other"] == 1
        assert result["H1"]["pass"] == 0
        assert result["H1"]["fail"] == 0

    def test_empty_inputs(self):
        result = parse_oscap.build_group_results([], {})
        assert result == {}

    def test_checks_stored_in_group(self):
        checks = [{"name": "check-a", "result": "pass"}]
        check_to_group = {"check-a": "H1"}
        result = parse_oscap.build_group_results(checks, check_to_group)
        assert len(result["H1"]["checks"]) == 1
        assert result["H1"]["checks"][0]["name"] == "check-a"


# --- write_failing_list ---


class TestWriteFailingList:
    def test_writes_sorted_names(self, tmpdir):
        failing = [
            {"name": "zebra-check", "result": "fail"},
            {"name": "alpha-check", "result": "fail"},
            {"name": "mid-check", "result": "fail"},
        ]
        filepath = os.path.join(tmpdir, "failing.txt")
        parse_oscap.write_failing_list(failing, {}, filepath)
        with open(filepath) as f:
            lines = f.read().strip().split("\n")
        assert lines == ["alpha-check", "mid-check", "zebra-check"]

    def test_empty_list(self, tmpdir):
        filepath = os.path.join(tmpdir, "failing.txt")
        parse_oscap.write_failing_list([], {}, filepath)
        with open(filepath) as f:
            content = f.read()
        assert content == ""
