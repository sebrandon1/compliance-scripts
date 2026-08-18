#!/usr/bin/env python3
"""
Validate dashboard JSON data files for structural correctness.

Checks docs/_data scan exports, tracking files, scan-history.json,
group-matrix.json, and upstream-prs.json against expected schemas
to prevent malformed data from breaking the live dashboard.

Usage: python3 scripts/validate-dashboard-data.py [docs/_data/]
"""
from __future__ import annotations

import json
import os
import re
import sys
import glob
from typing import Any

ISO8601_PATTERN = re.compile(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
)


PROFILE_PREFIXES = [
    "rhcos4-e8-master-", "rhcos4-e8-worker-", "rhcos4-e8-",
    "rhcos4-moderate-master-", "rhcos4-moderate-worker-", "rhcos4-moderate-",
    "ocp4-e8-", "ocp4-cis-", "ocp4-moderate-", "ocp4-pci-dss-",
]


def strip_profile_prefix(name: str) -> str:
    """Strip profile/role prefix from a check name."""
    for prefix in PROFILE_PREFIXES:
        if name.startswith(prefix):
            return name[len(prefix):]
    return name


def validate_scan_export(filepath: str) -> list[str]:
    """Validate an ocp-X_XX.json scan export file."""
    errors = []
    with open(filepath) as f:
        data = json.load(f)

    required_top = {"version", "scan_date", "summary", "remediations"}
    missing_top = required_top - set(data.keys())
    if missing_top:
        errors.append(f"Missing top-level keys: {missing_top}")

    if "scan_date" in data:
        val = data["scan_date"]
        if not isinstance(val, str):
            errors.append(
                f"scan_date must be a string, got {type(val).__name__}"
            )
        elif not ISO8601_PATTERN.match(val):
            errors.append(
                f"scan_date must be ISO 8601 format "
                f"(YYYY-MM-DDTHH:MM:SSZ), got '{val}'"
            )

    if "summary" in data:
        required_summary = {
            "total_checks", "passing", "failing", "manual"
        }
        missing_summary = required_summary - set(data["summary"].keys())
        if missing_summary:
            errors.append(f"Missing summary fields: {missing_summary}")

        for field in ["total_checks", "passing", "failing", "manual"]:
            val = data["summary"].get(field)
            if val is not None and not isinstance(val, int):
                errors.append(f"summary.{field} must be int, got {type(val).__name__}")

        total = data["summary"].get("total_checks", 0)
        parts = (
            data["summary"].get("passing", 0)
            + data["summary"].get("failing", 0)
            + data["summary"].get("manual", 0)
            + data["summary"].get("skipped", 0)
        )
        if total > 0 and parts != total:
            errors.append(
                f"summary counts don't add up: "
                f"passing({data['summary'].get('passing', 0)}) + "
                f"failing({data['summary'].get('failing', 0)}) + "
                f"manual({data['summary'].get('manual', 0)}) + "
                f"skipped({data['summary'].get('skipped', 0)}) = "
                f"{parts}, expected {total}"
            )

    if "remediations" in data:
        for severity in ["high", "medium", "low"]:
            items = data["remediations"].get(severity, [])
            if not isinstance(items, list):
                errors.append(f"remediations.{severity} must be a list")
                continue
            for i, item in enumerate(items):
                for field in ["name", "status", "severity"]:
                    if field not in item:
                        errors.append(
                            f"remediations.{severity}[{i}] missing '{field}'"
                        )

    if "passing_checks" in data:
        if not isinstance(data["passing_checks"], dict):
            errors.append("'passing_checks' must be a dict")
        else:
            for severity in ["high", "medium", "low"]:
                items = data["passing_checks"].get(severity, [])
                if not isinstance(items, list):
                    errors.append(
                        f"passing_checks.{severity} must be a list"
                    )
                    continue
                for i, item in enumerate(items):
                    if "name" not in item:
                        errors.append(
                            f"passing_checks.{severity}[{i}] missing 'name'"
                        )

    if "exported_at" in data:
        val = data["exported_at"]
        if not isinstance(val, str):
            errors.append(
                f"exported_at must be a string, got {type(val).__name__}"
            )
        elif not ISO8601_PATTERN.match(val):
            errors.append(
                f"exported_at must be ISO 8601 format "
                f"(YYYY-MM-DDTHH:MM:SSZ), got '{val}'"
            )

    if "manual_checks" in data:
        if not isinstance(data["manual_checks"], list):
            errors.append("'manual_checks' must be a list")
        else:
            for i, item in enumerate(data["manual_checks"]):
                if "name" not in item:
                    errors.append(
                        f"manual_checks[{i}] missing 'name'"
                    )

    return errors


def validate_tracking(filepath: str) -> list[str]:
    """Validate tracking.json structure and field consistency."""
    errors = []
    with open(filepath) as f:
        data = json.load(f)

    required_top = {"meta", "groups", "remediations"}
    missing_top = required_top - set(data.keys())
    if missing_top:
        errors.append(f"Missing top-level keys: {missing_top}")

    if "groups" in data:
        if not isinstance(data["groups"], dict):
            errors.append("'groups' must be a dict")
        else:
            errors.extend(_validate_tracking_groups(data["groups"]))

    if "remediations" in data:
        if not isinstance(data["remediations"], dict):
            errors.append("'remediations' must be a dict")
        else:
            errors.extend(_validate_tracking_remediations(
                data["remediations"],
                set(data.get("groups", {}).keys())
            ))

    return errors


# Valid enum values for tracking group fields
VALID_SEVERITIES = {"HIGH", "MEDIUM", "LOW", "MANUAL"}
VALID_PLATFORMS = {"rhcos", "ocp", "mixed"}
VALID_STATUSES = {
    "verified", "verified-needed", "partial", "pending",
    "not-applicable",
}
VALID_STATUS_PREFIXES = ("pass-vanilla",)
VALID_PRIORITY_LABELS = {"Critical", "High", "Medium", "Low"}
VALID_PR_STATES = {"open", "closed", "merged"}
VALID_UPSTREAM_VERDICTS = {
    "upstream-candidate", "upstream-pr-exists", "upstream-pr",
    "ran-only", "pass-vanilla", "platform-config",
    "site-specific", "not-applicable",
}
GROUP_ID_PATTERN = re.compile(r'^(H|M|L|MAN)\d+$')
VERSION_SLUG_PATTERN = re.compile(r'^\d+_\d+$')
MATRIX_CELL_FIELDS = ("pass", "fail", "manual", "total")
MATRIX_META_KEYS = {"description", "note"}
UPSTREAM_PR_REQUIRED = {"number", "title", "url", "state"}


def _validate_tracking_groups(groups: dict[str, Any]) -> list[str]:
    """Validate all groups in a tracking file."""
    errors = []
    group_ids = set(groups.keys())

    required_group_fields = {
        "title", "severity", "priority", "status", "platform"
    }

    for gid, group in groups.items():
        prefix = f"groups.{gid}"

        # Group ID format
        if not GROUP_ID_PATTERN.match(gid):
            errors.append(
                f"{prefix}: invalid group ID format "
                f"(expected H#, M#, L#, or MAN#)"
            )

        # Required fields
        missing = required_group_fields - set(group.keys())
        if missing:
            errors.append(f"{prefix} missing fields: {missing}")

        # Severity enum
        if group.get("severity") not in VALID_SEVERITIES:
            errors.append(
                f"{prefix} invalid severity: "
                f"'{group.get('severity')}'"
            )

        # Platform enum
        if group.get("platform") not in VALID_PLATFORMS:
            errors.append(
                f"{prefix} invalid platform: "
                f"'{group.get('platform')}'"
            )

        # Status: must be a known value or start with a known prefix
        status = group.get("status")
        if status is not None:
            status_ok = (
                status in VALID_STATUSES
                or any(
                    status.startswith(p) for p in VALID_STATUS_PREFIXES
                )
            )
            if not status_ok:
                errors.append(
                    f"{prefix} invalid status: '{status}'"
                )

        # Priority must be int
        priority = group.get("priority")
        if priority is not None and not isinstance(priority, int):
            errors.append(
                f"{prefix} priority must be int, "
                f"got {type(priority).__name__}"
            )

        # Priority label enum (optional field)
        plabel = group.get("priority_label")
        if plabel is not None and plabel not in VALID_PRIORITY_LABELS:
            errors.append(
                f"{prefix} invalid priority_label: '{plabel}'"
            )

        # String-or-null fields
        for field in ["title", "jira", "compare", "status_note",
                      "jira_status", "last_sync"]:
            val = group.get(field)
            if val is not None and not isinstance(val, str):
                errors.append(
                    f"{prefix} {field} must be string or null, "
                    f"got {type(val).__name__}"
                )

        # pr: string or int or null (some files use int PR numbers)
        pr_val = group.get("pr")
        if pr_val is not None and not isinstance(pr_val, (str, int)):
            errors.append(
                f"{prefix} pr must be string, int, or null, "
                f"got {type(pr_val).__name__}"
            )

        # pr_state enum (nullable)
        pr_state = group.get("pr_state")
        if pr_state is not None and pr_state not in VALID_PR_STATES:
            errors.append(
                f"{prefix} invalid pr_state: '{pr_state}'"
            )

        # prev_group / next_group must reference valid group IDs or null
        for nav in ["prev_group", "next_group"]:
            nav_val = group.get(nav)
            if nav_val is not None and nav_val not in group_ids:
                errors.append(
                    f"{prefix} {nav} references unknown "
                    f"group '{nav_val}'"
                )

        # upstream_verdict enum (optional, nullable)
        verdict = group.get("upstream_verdict")
        if verdict is not None and verdict not in VALID_UPSTREAM_VERDICTS:
            errors.append(
                f"{prefix} invalid upstream_verdict: '{verdict}'"
            )

        # upstream must be a list if present
        upstream = group.get("upstream")
        if upstream is not None:
            if not isinstance(upstream, list):
                errors.append(f"{prefix} upstream must be a list")
            else:
                for i, entry in enumerate(upstream):
                    if not isinstance(entry, dict):
                        errors.append(
                            f"{prefix} upstream[{i}] must be "
                            f"an object"
                        )

    return errors


def _validate_tracking_remediations(
    remediations: dict[str, Any],
    group_ids: set[str],
) -> list[str]:
    """Validate all remediations in a tracking file."""
    errors = []

    for rem_name, rem in remediations.items():
        prefix = f"remediations.{rem_name}"

        if not isinstance(rem, dict):
            errors.append(f"{prefix} must be an object")
            continue

        if "group" not in rem:
            errors.append(f"{prefix} missing 'group'")
        elif rem["group"] not in group_ids:
            errors.append(
                f"{prefix} references unknown group '{rem['group']}'"
            )

        # Optional string fields
        for field in ["description", "file"]:
            val = rem.get(field)
            if val is not None and not isinstance(val, str):
                errors.append(
                    f"{prefix} {field} must be string or null, "
                    f"got {type(val).__name__}"
                )

        # certsuite can be a string or a list of objects
        certsuite = rem.get("certsuite")
        if certsuite is not None:
            if isinstance(certsuite, list):
                for i, entry in enumerate(certsuite):
                    if not isinstance(entry, dict):
                        errors.append(
                            f"{prefix} certsuite[{i}] must be "
                            f"an object"
                        )
            elif not isinstance(certsuite, str):
                errors.append(
                    f"{prefix} certsuite must be string, list, "
                    f"or null, got {type(certsuite).__name__}"
                )

    return errors


def validate_scan_history(filepath: str) -> list[str]:
    """Validate scan-history.json structure."""
    errors = []
    with open(filepath) as f:
        data = json.load(f)

    if not isinstance(data, list):
        errors.append("scan-history.json must be a JSON array")
        return errors

    required_fields = {"version", "scan_date", "summary"}
    for i, entry in enumerate(data):
        if not isinstance(entry, dict):
            errors.append(f"Entry [{i}] must be an object")
            continue

        missing = required_fields - set(entry.keys())
        if missing:
            errors.append(f"Entry [{i}] missing fields: {missing}")

        sd = entry.get("scan_date")
        if sd is not None:
            if not isinstance(sd, str):
                errors.append(
                    f"Entry [{i}] scan_date must be a string, "
                    f"got {type(sd).__name__}"
                )
            elif not ISO8601_PATTERN.match(sd):
                errors.append(
                    f"Entry [{i}] scan_date must be ISO 8601 format "
                    f"(YYYY-MM-DDTHH:MM:SSZ), got '{sd}'"
                )

        if "summary" in entry:
            summary = entry["summary"]
            for field in ["total_checks", "passing", "failing", "manual"]:
                val = summary.get(field)
                if val is not None and not isinstance(val, int):
                    errors.append(
                        f"Entry [{i}] summary.{field} must be int, "
                        f"got {type(val).__name__}"
                    )

    return errors


def validate_group_matrix(filepath: str) -> list[str]:
    """Validate group-matrix.json structure used by the Hardened page."""
    errors = []
    with open(filepath) as f:
        data = json.load(f)

    if not isinstance(data, dict):
        errors.append("group-matrix.json must be a JSON object")
        return errors

    for gid, entry in data.items():
        prefix = gid
        if not GROUP_ID_PATTERN.match(gid):
            errors.append(
                f"{prefix}: invalid group ID format "
                f"(expected H#, M#, L#, or MAN#)"
            )
        if not isinstance(entry, dict):
            errors.append(f"{prefix} must be an object")
            continue

        version_cells = 0
        for key, val in entry.items():
            if key in MATRIX_META_KEYS:
                if val is not None and not isinstance(val, str):
                    errors.append(
                        f"{prefix}.{key} must be a string, "
                        f"got {type(val).__name__}"
                    )
                continue
            if not VERSION_SLUG_PATTERN.match(key):
                errors.append(f"{prefix}.{key}: unexpected key")
                continue
            version_cells += 1
            cell_prefix = f"{prefix}.{key}"
            if not isinstance(val, dict):
                errors.append(f"{cell_prefix} must be an object")
                continue
            missing = set(MATRIX_CELL_FIELDS) - set(val.keys())
            if missing:
                errors.append(f"{cell_prefix} missing fields: {missing}")
            for field in MATRIX_CELL_FIELDS:
                count = val.get(field)
                if field not in val:
                    continue
                if not isinstance(count, int):
                    errors.append(
                        f"{cell_prefix}.{field} must be int, "
                        f"got {type(count).__name__}"
                    )
                elif count < 0:
                    errors.append(
                        f"{cell_prefix}.{field} must be >= 0, got {count}"
                    )

        if version_cells == 0:
            errors.append(f"{prefix}: no version cells")

    return errors


def validate_upstream_prs(filepath: str) -> list[str]:
    """Validate upstream-prs.json structure used by the Hardened page."""
    errors = []
    with open(filepath) as f:
        data = json.load(f)

    if not isinstance(data, dict):
        errors.append("upstream-prs.json must be a JSON object")
        return errors

    for category, prs in data.items():
        if not isinstance(prs, list):
            errors.append(f"{category} must be a list")
            continue
        for i, pr in enumerate(prs):
            prefix = f"{category}[{i}]"
            if not isinstance(pr, dict):
                errors.append(f"{prefix} must be an object")
                continue
            missing = UPSTREAM_PR_REQUIRED - set(pr.keys())
            if missing:
                errors.append(f"{prefix} missing fields: {missing}")
            number = pr.get("number")
            if "number" in pr and not isinstance(number, int):
                errors.append(
                    f"{prefix} number must be int, got {type(number).__name__}"
                )
            title = pr.get("title")
            if "title" in pr and not isinstance(title, str):
                errors.append(
                    f"{prefix} title must be a string, "
                    f"got {type(title).__name__}"
                )
            url = pr.get("url")
            if "url" in pr:
                if not isinstance(url, str):
                    errors.append(
                        f"{prefix} url must be a string, "
                        f"got {type(url).__name__}"
                    )
                elif not url.startswith("https://"):
                    errors.append(f"{prefix} url must be an https URL")
            state = pr.get("state")
            if "state" in pr:
                if not isinstance(state, str):
                    errors.append(
                        f"{prefix} state must be a string, "
                        f"got {type(state).__name__}"
                    )
                elif state not in VALID_PR_STATES:
                    errors.append(f"{prefix} invalid state: '{state}'")

    return errors


def validate_cross_references(
    scan_filepath: str, tracking_filepath: str
) -> list[str]:
    """Cross-validate tracking remediation names against scan data."""
    errors = []
    with open(scan_filepath) as f:
        scan_data = json.load(f)
    with open(tracking_filepath) as f:
        tracking_data = json.load(f)

    scan_names: set[str] = set()
    for section in ["remediations", "passing_checks"]:
        for severity in ["high", "medium", "low"]:
            for item in scan_data.get(section, {}).get(severity, []):
                scan_names.add(strip_profile_prefix(item["name"]))
    for item in scan_data.get("manual_checks", []):
        scan_names.add(strip_profile_prefix(item["name"]))

    tracking_rems = tracking_data.get("remediations", {})
    missing = sorted(r for r in tracking_rems if r not in scan_names)

    if missing:
        sample = ", ".join(missing[:10])
        suffix = f" (and {len(missing) - 10} more)" if len(missing) > 10 else ""
        errors.append(
            f"{len(missing)} tracking remediation(s) not found in scan data: "
            f"{sample}{suffix}"
        )

    return errors


def main() -> None:
    data_dir = sys.argv[1] if len(sys.argv) > 1 else "docs/_data"

    if not os.path.isdir(data_dir):
        print(f"ERROR: Directory not found: {data_dir}", file=sys.stderr)
        sys.exit(1)

    all_errors = {}
    total_files = 0

    scan_files = glob.glob(os.path.join(data_dir, "ocp-*.json"))
    for filepath in sorted(scan_files):
        if "baseline" in filepath:
            continue
        total_files += 1
        basename = os.path.basename(filepath)
        print(f"Validating {basename}...", end=" ")
        errors = validate_scan_export(filepath)
        if errors:
            print("FAIL")
            all_errors[basename] = errors
        else:
            print("OK")

    tracking_files = (
        glob.glob(os.path.join(data_dir, "tracking.json"))
        + glob.glob(os.path.join(data_dir, "tracking-*.json"))
    )
    for filepath in sorted(tracking_files):
        total_files += 1
        basename = os.path.basename(filepath)
        print(f"Validating {basename}...", end=" ")
        errors = validate_tracking(filepath)
        if errors:
            print("FAIL")
            all_errors[basename] = errors
        else:
            print("OK")

    named_validators = (
        ("scan-history.json", validate_scan_history),
        ("group-matrix.json", validate_group_matrix),
        ("upstream-prs.json", validate_upstream_prs),
    )
    for filename, validator in named_validators:
        filepath = os.path.join(data_dir, filename)
        if not os.path.exists(filepath):
            continue
        total_files += 1
        print(f"Validating {filename}...", end=" ")
        errors = validator(filepath)
        if errors:
            print("FAIL")
            all_errors[filename] = errors
        else:
            print("OK")

    # Cross-reference: tracking remediations vs scan data (warnings only)
    xref_warnings: dict[str, list[str]] = {}
    for filepath in sorted(scan_files):
        if "baseline" in filepath:
            continue
        basename = os.path.basename(filepath)
        version_slug = basename.replace("ocp-", "").replace(".json", "")
        tracking_path = os.path.join(data_dir, f"tracking-{version_slug}.json")
        if not os.path.exists(tracking_path):
            tracking_path = os.path.join(data_dir, "tracking.json")
        if os.path.exists(tracking_path):
            xref_label = f"{basename} <-> {os.path.basename(tracking_path)}"
            print(f"Cross-referencing {xref_label}...", end=" ")
            errors = validate_cross_references(filepath, tracking_path)
            if errors:
                print("WARN")
                xref_warnings[xref_label] = errors
            else:
                print("OK")

    if xref_warnings:
        print()
        print(f"WARNINGS: {len(xref_warnings)} cross-reference issue(s):")
        for label, warnings in xref_warnings.items():
            print(f"\n  {label}:")
            for w in warnings:
                print(f"    - {w}")

    print()
    if all_errors:
        print(f"FAILED: {len(all_errors)} file(s) with errors:")
        for filename, errors in all_errors.items():
            print(f"\n  {filename}:")
            for err in errors:
                print(f"    - {err}")
        sys.exit(1)
    else:
        print(f"All {total_files} file(s) valid.")


if __name__ == "__main__":
    main()
