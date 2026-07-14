#!/usr/bin/env python3
"""
Suggest remediation groups for ungrouped compliance checks.

Analyzes check names against existing group mappings in tracking.json
to suggest which group new or ungrouped checks belong to. Uses prefix
matching, semantic rules, and substring matching.
"""
from __future__ import annotations

import json
import sys
import argparse
from collections import defaultdict
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TRACKING = REPO_ROOT / "docs" / "_data" / "tracking.json"

HIGH_THRESHOLD = 0.9
MEDIUM_THRESHOLD = 0.5

SYSCTL_RULES = [
    ("sysctl-kernel-dmesg", "L2", 0.95, "sysctl dmesg_restrict"),
    ("sysctl-kernel", "M23", 0.85, "kernel.* sysctl → M23"),
    ("sysctl-net", "M22", 0.90, "net.* sysctl → M22"),
    ("sysctl-fs", "M2", 0.80, "fs.* sysctl → M2"),
]


def load_tracking(path: str | Path) -> dict[str, Any]:
    with open(path) as f:
        return json.load(f)


def build_prefix_map(
    tracking: dict[str, Any],
) -> tuple[
    dict[str, dict[str, int]],
    dict[str, list[str]],
    dict[str, str],
]:
    """Build prefix→{group_id: count} and keyword→group_id maps."""
    groups = tracking.get("groups", {})
    group_checks = defaultdict(list)
    for check, info in tracking.get("remediations", {}).items():
        group_checks[info["group"]].append(check)

    prefix_map = defaultdict(lambda: defaultdict(int))
    for gid, checks in group_checks.items():
        for check in checks:
            parts = check.split("-")
            for depth in range(1, min(len(parts) + 1, 7)):
                pfx = "-".join(parts[:depth])
                prefix_map[pfx][gid] += 1

    kw_map = {}
    for gid, g in groups.items():
        for word in g.get("title", "").lower().split():
            if len(word) > 3:
                kw_map[word] = gid
    for gid, checks in group_checks.items():
        for existing in checks:
            for token in existing.split("-"):
                if len(token) > 3:
                    kw_map[token] = gid

    return prefix_map, group_checks, kw_map


def suggest_group(
    check_name: str,
    prefix_map: dict[str, dict[str, int]],
    kw_map: dict[str, str],
) -> tuple[str | None, float, str]:
    """Suggest the best group for a check name. Returns (group_id, confidence, reason)."""
    parts = check_name.split("-")

    if check_name.startswith("sysctl-"):
        for prefix, gid, conf, reason in SYSCTL_RULES:
            if check_name.startswith(prefix):
                return gid, conf, reason

    best_group = None
    best_confidence = 0.0
    best_reason = ""

    for depth in range(min(len(parts), 6), 0, -1):
        pfx = "-".join(parts[:depth])
        if pfx not in prefix_map:
            continue

        candidates = prefix_map[pfx]
        if len(candidates) == 1:
            gid = list(candidates.keys())[0]
            conf = min(0.95, 0.7 + depth * 0.05)
            if conf > best_confidence:
                best_group = gid
                best_confidence = conf
                best_reason = f"prefix '{pfx}' unique to {gid}"
            break
        else:
            top = max(candidates.items(), key=lambda x: x[1])
            total = sum(candidates.values())
            dominance = top[1] / total
            conf = min(0.85, 0.4 + dominance * 0.3 + depth * 0.05)
            if conf > best_confidence:
                best_group = top[0]
                best_confidence = conf
                best_reason = (
                    f"prefix '{pfx}' → {top[0]} "
                    f"({top[1]}/{total} checks)"
                )

    if best_group and best_confidence >= MEDIUM_THRESHOLD:
        return best_group, best_confidence, best_reason

    for token in parts:
        if token in kw_map:
            gid = kw_map[token]
            return gid, MEDIUM_THRESHOLD, f"keyword '{token}' found in {gid}"

    return None, 0.0, "no match"


def extract_check_names_from_scan(scan_data: dict[str, Any]) -> set[str]:
    """Extract all unique check names from a scan export JSON."""
    names = set()
    for section in ["remediations", "passing_checks"]:
        for severity in ["high", "medium", "low"]:
            for item in scan_data.get(section, {}).get(severity, []):
                names.add(item["name"])
    for item in scan_data.get("manual_checks", []):
        names.add(item["name"])
    return names


def strip_profile_prefix(name: str) -> str:
    """Strip profile/role prefix from a check name.
    rhcos4-e8-master-sshd-disable-root-login → sshd-disable-root-login
    ocp4-cis-api-server-encryption → api-server-encryption
    """
    for prefix in [
        "rhcos4-e8-master-", "rhcos4-e8-worker-", "rhcos4-e8-",
        "rhcos4-moderate-master-", "rhcos4-moderate-worker-", "rhcos4-moderate-",
        "ocp4-e8-", "ocp4-cis-", "ocp4-moderate-", "ocp4-pci-dss-",
    ]:
        if name.startswith(prefix):
            return name[len(prefix):]
    return name


def print_section(
    label: str,
    checks: list[dict[str, Any]],
    groups: dict[str, Any],
    show_confidence: bool = True,
) -> None:
    if not checks:
        return
    print(f"{label} — {len(checks)} checks:")
    for r in checks:
        if show_confidence:
            g = r["group"] or "?"
            title = groups.get(g, {}).get("title", "")
            print(f"  {r['check']:<55s} → {g:<5s} ({title})  [{r['confidence']:.2f}]")
        else:
            print(f"  {r['check']}")
    print()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Suggest remediation groups for ungrouped compliance checks",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Examples:
  %(prog)s docs/_data/ocp-5_0.json
  %(prog)s --tracking docs/_data/tracking-5_0.json docs/_data/ocp-5_0.json
  %(prog)s --checks "chronyd-configure-local-socket,new-check"
  %(prog)s --json docs/_data/ocp-5_0.json
""",
    )
    parser.add_argument("scan", nargs="?", help="Scan export JSON file")
    parser.add_argument("--tracking", default=str(DEFAULT_TRACKING),
                        help="Path to tracking.json")
    parser.add_argument("--checks", help="Comma-separated check names")
    parser.add_argument("--from-diff", action="store_true",
                        help="Read diff-scans --json output from stdin")
    parser.add_argument("--json", action="store_true",
                        help="Output as JSON")
    parser.add_argument("--all", action="store_true",
                        help="Show all checks including already-grouped ones")
    args = parser.parse_args()

    tracking = load_tracking(args.tracking)
    prefix_map, group_checks, kw_map = build_prefix_map(tracking)
    groups = tracking.get("groups", {})
    tracked_checks = set(tracking.get("remediations", {}).keys())

    ungrouped = []

    if args.checks:
        for name in args.checks.split(","):
            name = name.strip()
            if name:
                ungrouped.append(strip_profile_prefix(name))
    elif args.from_diff:
        diff_data = json.load(sys.stdin)
        for item in diff_data.get("added", []):
            name = strip_profile_prefix(item.get("name", item) if isinstance(item, dict) else item)
            ungrouped.append(name)
    elif args.scan:
        with open(args.scan) as f:
            scan_data = json.load(f)
        all_checks = extract_check_names_from_scan(scan_data)
        stripped = {strip_profile_prefix(c) for c in all_checks}
        if args.all:
            ungrouped = sorted(stripped)
        else:
            ungrouped = sorted(stripped - tracked_checks)
    else:
        parser.print_help()
        sys.exit(1)

    ungrouped = sorted(set(ungrouped))

    results = []
    for check in ungrouped:
        if check in tracked_checks and not args.all:
            continue
        if check in tracked_checks:
            gid = tracking["remediations"][check]["group"]
            results.append({
                "check": check, "group": gid, "confidence": 1.0,
                "reason": "already tracked",
            })
            continue

        gid, conf, reason = suggest_group(check, prefix_map, kw_map)
        results.append({
            "check": check, "group": gid, "confidence": conf,
            "reason": reason,
        })

    if args.json:
        json.dump(results, sys.stdout, indent=2)
        print()
        return

    tracked_count = len(tracked_checks)
    group_count = len(groups)
    print("=" * 65)
    print("  AUTO-GROUPING SUGGESTIONS")
    print("=" * 65)
    print(f"  Tracking: {args.tracking} ({tracked_count} mapped, {group_count} groups)")
    if args.scan:
        print(f"  Scan: {args.scan}")
    print(f"  Ungrouped: {len(results)} check(s)")
    print()

    high, medium, low, no_match = [], [], [], []
    for r in results:
        c = r["confidence"]
        if c >= HIGH_THRESHOLD:
            high.append(r)
        elif c >= MEDIUM_THRESHOLD:
            medium.append(r)
        elif c > 0.0:
            low.append(r)
        else:
            no_match.append(r)

    print_section(f"HIGH CONFIDENCE (>= {HIGH_THRESHOLD})", high, groups)
    print_section(f"MEDIUM CONFIDENCE ({MEDIUM_THRESHOLD}-{HIGH_THRESHOLD})", medium, groups)
    print_section(f"LOW CONFIDENCE (< {MEDIUM_THRESHOLD})", low, groups)
    print_section("NEW GROUP CANDIDATES", no_match, groups, show_confidence=False)

    matched = len(high) + len(medium)
    total = len(results)
    if total > 0:
        print(f"Summary: {matched}/{total} checks have suggestions "
              f"({len(high)} high, {len(medium)} medium, {len(low)} low, {len(no_match)} unmatched)")


if __name__ == "__main__":
    main()
