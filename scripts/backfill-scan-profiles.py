#!/usr/bin/env python3
"""Backfill per-profile breakdowns into scan-history.json.

For each scan-history entry, find the matching detailed scan file and
compute pass/fail/manual counts per compliance profile (E8, CIS, Moderate, PCI-DSS).
"""

import json
import os
from collections import Counter
from typing import Optional


def compute_profiles(scan_file: str) -> Optional[dict[str, dict[str, int]]]:
    """Compute per-profile pass/fail/manual from a detailed scan file."""
    with open(scan_file) as fh:
        scan = json.load(fh)

    profile_pass: Counter[str] = Counter()
    profile_fail: Counter[str] = Counter()
    profile_manual: Counter[str] = Counter()

    for sev_checks in scan.get("passing_checks", {}).values():
        for check in sev_checks:
            profile = check.get("profile", "")
            if profile:
                profile_pass[profile] += 1

    for sev_checks in scan.get("remediations", {}).values():
        for check in sev_checks:
            profile = check.get("profile", "")
            if profile:
                profile_fail[profile] += 1

    for check in scan.get("manual_checks", []):
        profile = check.get("profile", "")
        if profile:
            profile_manual[profile] += 1

    all_profiles = sorted(set(profile_pass) | set(profile_fail) | set(profile_manual))
    if not all_profiles:
        return None

    return {
        p: {
            "passing": profile_pass[p],
            "failing": profile_fail[p],
            "manual": profile_manual[p],
        }
        for p in all_profiles
    }


def find_scan_file(entry: dict[str, object], data_dir: str) -> Optional[str]:
    """Find the best matching scan file for a history entry."""
    version = str(entry.get("version", ""))
    scan_date = str(entry.get("scan_date", ""))
    vs = version.replace(".", "_")
    date_str = scan_date[:10]

    candidates = [
        os.path.join(data_dir, f"ocp-{vs}-{date_str}.json"),
        os.path.join(data_dir, f"ocp-{vs}-baseline-{date_str}.json"),
        os.path.join(data_dir, f"ocp-{vs}.json"),
    ]

    for candidate in candidates:
        if os.path.exists(candidate):
            return candidate

    return None


def main() -> None:
    data_dir = os.path.normpath(
        os.path.join(os.path.dirname(__file__), "..", "docs", "_data")
    )

    history_file = os.path.join(data_dir, "scan-history.json")
    with open(history_file) as fh:
        history = json.load(fh)

    updated = 0
    for entry in history:
        scan_file = find_scan_file(entry, data_dir)
        if scan_file:
            profiles = compute_profiles(scan_file)
            if profiles:
                entry["profiles"] = profiles
                updated += 1
                print(
                    f"  {entry['scan_date'][:10]} {entry['version']}: "
                    f"{len(profiles)} profiles from {os.path.basename(scan_file)}"
                )
                continue

        entry["profiles"] = None
        print(f"  {entry['scan_date'][:10]} {entry['version']}: no profile data")

    with open(history_file, "w") as fh:
        json.dump(history, fh, indent=2)
        fh.write("\n")

    print(f"\nUpdated {updated}/{len(history)} entries with profile data")


if __name__ == "__main__":
    main()
