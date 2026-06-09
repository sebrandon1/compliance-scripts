#!/usr/bin/env python3
"""
Compare two compliance scan export files and report differences.

Shows status changes (PASS->FAIL, FAIL->PASS), new checks, removed checks,
and summary delta. Useful for detecting regressions after cluster rebuilds,
OCP upgrades, or content image updates.

Usage:
    python3 scripts/diff-scans.py <old.json> <new.json>
    python3 scripts/diff-scans.py docs/_data/ocp-4_22-baseline-2026-05-05.json docs/_data/ocp-4_22.json
    python3 scripts/diff-scans.py --json <old.json> <new.json>
"""
import json
import sys
import argparse

SEVERITIES = ["high", "medium", "low"]


def build_check_map(data):
    """Build a name -> {status, severity, platform, profile} map from export data."""
    checks = {}
    for section, status in [("remediations", "FAIL"), ("passing_checks", "PASS")]:
        for severity in SEVERITIES:
            for item in data.get(section, {}).get(severity, []):
                checks[item["name"]] = {
                    "status": status,
                    "severity": item.get("severity", severity),
                    "platform": item.get("platform", ""),
                    "profile": item.get("profile", ""),
                }
    for item in data.get("manual_checks", []):
        checks[item["name"]] = {
            "status": "MANUAL",
            "severity": item.get("severity", ""),
            "platform": item.get("platform", ""),
            "profile": item.get("profile", ""),
        }
    return checks


def diff_scans(old_data, new_data):
    """Compare two scan exports and return structured diff."""
    old_checks = build_check_map(old_data)
    new_checks = build_check_map(new_data)

    common = set(old_checks) & set(new_checks)
    added = sorted(set(new_checks) - set(old_checks))
    removed = sorted(set(old_checks) - set(new_checks))

    pass_to_fail = []
    fail_to_pass = []
    manual_changes = []

    for name in sorted(common):
        old_status = old_checks[name]["status"]
        new_status = new_checks[name]["status"]
        if old_status == new_status:
            continue
        entry = {
            "name": name,
            "old_status": old_status,
            "new_status": new_status,
            "platform": new_checks[name].get("platform", ""),
        }
        if old_status == "PASS" and new_status == "FAIL":
            pass_to_fail.append(entry)
        elif old_status == "FAIL" and new_status == "PASS":
            fail_to_pass.append(entry)
        else:
            manual_changes.append(entry)

    old_summary = old_data.get("summary", {})
    new_summary = new_data.get("summary", {})

    return {
        "old": {
            "version": old_data.get("version", "?"),
            "scan_date": old_data.get("scan_date", "?"),
            "summary": old_summary,
        },
        "new": {
            "version": new_data.get("version", "?"),
            "scan_date": new_data.get("scan_date", "?"),
            "summary": new_summary,
        },
        "pass_to_fail": pass_to_fail,
        "fail_to_pass": fail_to_pass,
        "manual_changes": manual_changes,
        "added": [{"name": n, **new_checks[n]} for n in added],
        "removed": [{"name": n, **old_checks[n]} for n in removed],
    }


def print_diff(result):
    """Print a human-readable diff report."""
    old = result["old"]
    new = result["new"]
    os = old["summary"]
    ns = new["summary"]

    print("=" * 65)
    print("  COMPLIANCE SCAN DIFF")
    print("=" * 65)
    print(f"  Old: v{old['version']}  {old['scan_date']}")
    print(f"  New: v{new['version']}  {new['scan_date']}")
    print()

    headers = ["", "Old", "New", "Delta"]
    rows = []
    for field in ["total_checks", "passing", "failing", "manual"]:
        o = os.get(field, 0)
        n = ns.get(field, 0)
        delta = n - o
        sign = "+" if delta > 0 else ""
        rows.append([field, str(o), str(n), f"{sign}{delta}"])

    col_widths = [max(len(r[i]) for r in [headers] + rows) for i in range(4)]
    fmt = "  {:<{}} {:>{}} {:>{}} {:>{}}"
    print(fmt.format(headers[0], col_widths[0], headers[1], col_widths[1],
                     headers[2], col_widths[2], headers[3], col_widths[3]))
    print("  " + "-" * (sum(col_widths) + 6))
    for row in rows:
        print(fmt.format(row[0], col_widths[0], row[1], col_widths[1],
                         row[2], col_widths[2], row[3], col_widths[3]))
    print()

    regressions = result["pass_to_fail"]
    fixes = result["fail_to_pass"]
    added = result["added"]
    removed = result["removed"]
    manual = result["manual_changes"]

    if regressions:
        ocp = [r for r in regressions if r["platform"] == "ocp"]
        rhcos = [r for r in regressions if r["platform"] != "ocp"]
        if ocp:
            print(f"REGRESSIONS (PASS -> FAIL) — OCP platform ({len(ocp)}):")
            for r in ocp:
                print(f"  {r['name']}")
            print()
        if rhcos:
            print(f"REGRESSIONS (PASS -> FAIL) — RHCOS node ({len(rhcos)}):")
            if len(rhcos) <= 20:
                for r in rhcos:
                    print(f"  {r['name']}")
            else:
                for r in rhcos[:10]:
                    print(f"  {r['name']}")
                print(f"  ... and {len(rhcos) - 10} more")
            print()

    if fixes:
        print(f"FIXES (FAIL -> PASS) ({len(fixes)}):")
        for r in fixes:
            print(f"  {r['name']}")
        print()

    if added:
        print(f"NEW CHECKS (not in old scan) ({len(added)}):")
        for r in added:
            print(f"  {r['status']}: {r['name']}")
        print()

    if removed:
        print(f"REMOVED CHECKS (not in new scan) ({len(removed)}):")
        for r in removed:
            print(f"  {r['name']}")
        print()

    if manual:
        print(f"OTHER STATUS CHANGES ({len(manual)}):")
        for r in manual:
            print(f"  {r['old_status']} -> {r['new_status']}: {r['name']}")
        print()

    total_changes = len(regressions) + len(fixes) + len(added) + len(removed) + len(manual)
    if total_changes == 0:
        print("No differences found.")
    else:
        print(f"Total: {total_changes} difference(s)")
        if regressions:
            print(
                f"  {len(regressions)} regression(s) "
                f"({len(ocp)} OCP, {len(rhcos)} RHCOS)"
            )


def main():
    parser = argparse.ArgumentParser(
        description="Compare two compliance scan exports and report differences",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Compare baseline to current
  %(prog)s docs/_data/ocp-4_22-baseline-2026-05-05.json docs/_data/ocp-4_22.json

  # Compare across versions
  %(prog)s docs/_data/ocp-4_21.json docs/_data/ocp-4_22.json

  # Output as JSON for scripting
  %(prog)s --json docs/_data/ocp-4_22-baseline-2026-05-05.json docs/_data/ocp-4_22.json
"""
    )
    parser.add_argument("old", help="Older scan export JSON file")
    parser.add_argument("new", help="Newer scan export JSON file")
    parser.add_argument("--json", action="store_true",
                        help="Output as JSON instead of human-readable")
    args = parser.parse_args()

    with open(args.old) as f:
        old_data = json.load(f)
    with open(args.new) as f:
        new_data = json.load(f)

    result = diff_scans(old_data, new_data)

    if args.json:
        json.dump(result, sys.stdout, indent=2)
        print()
    else:
        print_diff(result)

    has_regressions = len(result["pass_to_fail"]) > 0
    sys.exit(1 if has_regressions else 0)


if __name__ == "__main__":
    main()
