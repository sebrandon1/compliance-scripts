#!/usr/bin/env python3
"""Parse OSCAP XCCDF results XML and compare against tracking.json groups."""

import argparse
import json
import sys
import xml.etree.ElementTree as ET

XCCDF_NS = "http://checklists.nist.gov/xccdf/1.2"


def parse_results(results_file):
    """Parse XCCDF results XML and return check results."""
    tree = ET.parse(results_file)
    root = tree.getroot()

    checks = []
    for rule_result in root.iter(f"{{{XCCDF_NS}}}rule-result"):
        idref = rule_result.get("idref", "")
        result_elem = rule_result.find(f"{{{XCCDF_NS}}}result")
        result = result_elem.text if result_elem is not None else "unknown"

        short_name = idref.replace(
            "xccdf_org.ssgproject.content_rule_", ""
        ).replace("_", "-")

        checks.append({
            "id": idref,
            "name": short_name,
            "result": result,
        })

    return checks


def load_tracking(tracking_file):
    """Load tracking.json and build check-to-group mapping."""
    with open(tracking_file) as f:
        data = json.load(f)

    check_to_group = {}
    for check_name, info in data.get("remediations", {}).items():
        check_to_group[check_name] = info.get("group", "")

    groups = data.get("groups", {})
    return check_to_group, groups


def build_group_results(checks, check_to_group):
    """Aggregate check results by group."""
    group_results = {}
    for check in checks:
        group_id = check_to_group.get(check["name"], "")
        if group_id:
            if group_id not in group_results:
                group_results[group_id] = {
                    "pass": 0, "fail": 0, "other": 0, "checks": []
                }
            if check["result"] == "pass":
                group_results[group_id]["pass"] += 1
            elif check["result"] == "fail":
                group_results[group_id]["fail"] += 1
            else:
                group_results[group_id]["other"] += 1
            group_results[group_id]["checks"].append(check)

    return group_results


def count_results(checks):
    """Count results by status."""
    counts = {}
    for check in checks:
        counts[check["result"]] = counts.get(check["result"], 0) + 1
    return counts


def sort_group_key(x):
    """Sort groups: H < L < M < MAN, then by number."""
    prefix = ''.join(c for c in x if c.isalpha())
    num = int(''.join(c for c in x if c.isdigit()) or '0')
    order = {"H": 0, "L": 1, "M": 2, "MAN": 3}
    return (order.get(prefix, 99), num)


def print_summary(checks, output_format="text"):
    """Print scan result summary."""
    counts = count_results(checks)
    failing = [c for c in checks if c["result"] == "fail"]

    if output_format == "markdown":
        print("## Scan Summary\n")
        print("| Result | Count |")
        print("|--------|-------|")
        for result, count in sorted(counts.items()):
            print(f"| {result} | {count} |")
        print(f"\n**Total: {len(checks)} checks**\n")

        if failing:
            print("## Failing Checks\n")
            print("| Check | Group |")
            print("|-------|-------|")
    else:
        print("=== Scan Summary ===")
        for result, count in sorted(counts.items()):
            print(f"  {result}: {count}")
        print(f"  Total: {len(checks)}")

        if failing:
            print("\n=== Failing Checks ===")

    return failing


def print_group_comparison(group_results, groups, output_format="text"):
    """Print group-level comparison."""
    if output_format == "markdown":
        print("## Group Status on This RHCOS Version\n")
        print("| Group | Title | Status | PASS | FAIL | Verdict |")
        print("|-------|-------|--------|------|------|---------|")
    else:
        print("\n=== Group Comparison ===")

    for gid in sorted(group_results.keys(), key=sort_group_key):
        gr = group_results[gid]
        group_info = groups.get(gid, {})
        title = group_info.get("title", "Unknown")
        current_status = group_info.get("status", "unknown")

        is_pass_vanilla = "pass-vanilla" in current_status
        if gr["fail"] > 0 and is_pass_vanilla:
            verdict = "PASS on live cluster (static scan limitation)"
        elif gr["fail"] > 0:
            verdict = "NEEDS REMEDIATION"
        else:
            verdict = "PASS (no remediation needed)"

        if output_format == "markdown":
            print(
                f"| {gid} | {title} | {current_status} "
                f"| {gr['pass']} | {gr['fail']} | {verdict} |"
            )
        else:
            print(
                f"  {gid:6s} {title:35s} "
                f"pass={gr['pass']} fail={gr['fail']} -> {verdict}"
            )


def write_failing_list(failing, check_to_group, filepath):
    """Write sorted failing check names to a file for baseline comparison."""
    with open(filepath, "w") as f:
        for check in sorted(failing, key=lambda c: c["name"]):
            f.write(check["name"] + "\n")


def main():
    parser = argparse.ArgumentParser(description="Parse OSCAP XCCDF results")
    parser.add_argument("results", help="XCCDF results XML file")
    parser.add_argument(
        "--tracking", help="tracking.json file for group comparison"
    )
    parser.add_argument(
        "--format", choices=["text", "markdown", "json"], default="text"
    )
    parser.add_argument(
        "--failing-only", action="store_true",
        help="Only output failing checks"
    )
    parser.add_argument(
        "--markdown-file",
        help="Write markdown output to this file (in addition to stdout)"
    )
    parser.add_argument(
        "--failing-file",
        help="Write sorted failing check names to this file"
    )
    args = parser.parse_args()

    checks = parse_results(args.results)

    check_to_group, groups, group_results = {}, {}, {}
    if args.tracking:
        check_to_group, groups = load_tracking(args.tracking)
        group_results = build_group_results(checks, check_to_group)

    if args.format == "json":
        output = {
            "checks": checks,
            "summary": count_results(checks),
        }

        if args.tracking:
            output["groups"] = {}
            for gid, gr in group_results.items():
                output["groups"][gid] = {
                    "title": groups.get(gid, {}).get("title", ""),
                    "current_status": groups.get(gid, {}).get("status", ""),
                    "pass": gr["pass"],
                    "fail": gr["fail"],
                    "needs_remediation": gr["fail"] > 0,
                }

        if args.failing_only:
            output["checks"] = [
                c for c in checks if c["result"] == "fail"
            ]

        json.dump(output, sys.stdout, indent=2)
        print()
        return

    failing = print_summary(checks, args.format)

    if failing:
        for check in sorted(failing, key=lambda c: c["name"]):
            group_id = check_to_group.get(check["name"], "-")
            if args.format == "markdown":
                print(f"| `{check['name']}` | {group_id} |")
            else:
                print(f"  FAIL: {check['name']}")

    if args.tracking and not args.failing_only:
        print_group_comparison(group_results, groups, args.format)

    # Write optional output files (single-pass, no re-parsing)
    if args.failing_file and failing:
        write_failing_list(failing, check_to_group, args.failing_file)

    if args.markdown_file:
        import io
        old_stdout = sys.stdout
        sys.stdout = io.StringIO()
        print_summary(checks, "markdown")
        if failing:
            for check in sorted(failing, key=lambda c: c["name"]):
                group_id = check_to_group.get(check["name"], "-")
                print(f"| `{check['name']}` | {group_id} |")
        if args.tracking:
            print_group_comparison(group_results, groups, "markdown")
        md_content = sys.stdout.getvalue()
        sys.stdout = old_stdout
        with open(args.markdown_file, "w") as f:
            f.write(md_content)


if __name__ == "__main__":
    main()
