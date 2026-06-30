#!/usr/bin/env python3
"""
Validate dashboard JSON data files for structural correctness.

Checks docs/_data/ocp-*.json and tracking.json against expected schemas
to prevent malformed data from breaking the live dashboard.

Usage: python3 scripts/validate-dashboard-data.py [docs/_data/]
"""
import json
import os
import sys
import glob


def validate_scan_export(filepath):
    """Validate an ocp-X_XX.json scan export file."""
    errors = []
    with open(filepath) as f:
        data = json.load(f)

    required_top = {"version", "scan_date", "summary", "remediations"}
    missing_top = required_top - set(data.keys())
    if missing_top:
        errors.append(f"Missing top-level keys: {missing_top}")

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

    return errors


def validate_tracking(filepath):
    """Validate tracking.json structure."""
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
            required_group_fields = {
                "title", "severity", "priority", "status", "platform"
            }
            for gid, group in data["groups"].items():
                missing = required_group_fields - set(group.keys())
                if missing:
                    errors.append(
                        f"groups.{gid} missing fields: {missing}"
                    )

                valid_severities = {"HIGH", "MEDIUM", "LOW", "MANUAL"}
                if group.get("severity") not in valid_severities:
                    errors.append(
                        f"groups.{gid} invalid severity: "
                        f"'{group.get('severity')}'"
                    )

                valid_platforms = {"rhcos", "ocp", "mixed"}
                if group.get("platform") not in valid_platforms:
                    errors.append(
                        f"groups.{gid} invalid platform: "
                        f"'{group.get('platform')}'"
                    )

    if "remediations" in data:
        if not isinstance(data["remediations"], dict):
            errors.append("'remediations' must be a dict")
        else:
            group_ids = set(data.get("groups", {}).keys())
            for rem_name, rem in data["remediations"].items():
                if "group" not in rem:
                    errors.append(
                        f"remediations.{rem_name} missing 'group'"
                    )
                elif rem["group"] not in group_ids:
                    errors.append(
                        f"remediations.{rem_name} references "
                        f"unknown group '{rem['group']}'"
                    )

    return errors


def validate_scan_history(filepath):
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


def main():
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

    history_file = os.path.join(data_dir, "scan-history.json")
    if os.path.exists(history_file):
        total_files += 1
        print("Validating scan-history.json...", end=" ")
        errors = validate_scan_history(history_file)
        if errors:
            print("FAIL")
            all_errors["scan-history.json"] = errors
        else:
            print("OK")

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
