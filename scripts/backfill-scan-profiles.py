#!/usr/bin/env python3
"""Backfill per-profile breakdowns into scan-history.json.

For each scan-history entry, find the matching detailed scan file and
compute pass/fail/manual counts per compliance profile (E8, CIS, Moderate, PCI-DSS).
Entries that already have a profiles object are left unchanged.
"""

from __future__ import annotations

import json
import os
from collections import Counter
from collections.abc import Iterable
from typing import Optional


def _count_by_profile(checks: Iterable[dict]) -> Counter[str]:
    counts: Counter[str] = Counter()
    for check in checks:
        profile = check.get("profile") or ""
        if profile:
            counts[profile] += 1
    return counts


def _grouped_checks(scan: dict, key: str) -> list[dict]:
    checks: list[dict] = []
    for sev_checks in scan.get(key, {}).values():
        checks.extend(sev_checks)
    return checks


def profiles_from_scan(scan: dict) -> Optional[dict[str, dict[str, int]]]:
    """Compute per-profile pass/fail/manual from a parsed scan export."""
    profile_pass = _count_by_profile(_grouped_checks(scan, "passing_checks"))
    profile_fail = _count_by_profile(_grouped_checks(scan, "remediations"))
    profile_manual = _count_by_profile(scan.get("manual_checks", []))

    all_profiles = sorted(
        set(profile_pass) | set(profile_fail) | set(profile_manual)
    )
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


def compute_profiles(scan_file: str) -> Optional[dict[str, dict[str, int]]]:
    """Compute per-profile pass/fail/manual from a detailed scan file."""
    with open(scan_file) as fh:
        return profiles_from_scan(json.load(fh))


def find_scan_file(entry: dict, data_dir: str) -> Optional[str]:
    """Find the best matching scan file for a history entry.

    Prefer a dated export, then a dated baseline, then the undated latest file.
    """
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


def backfill_history(history: list[dict], data_dir: str) -> int:
    """Fill missing profiles on history entries. Returns how many were updated."""
    updated = 0
    for entry in history:
        if isinstance(entry.get("profiles"), dict):
            continue

        scan_file = find_scan_file(entry, data_dir)
        profiles = compute_profiles(scan_file) if scan_file else None
        entry["profiles"] = profiles
        if profiles:
            updated += 1
    return updated


def default_data_dir() -> str:
    return os.path.normpath(
        os.path.join(os.path.dirname(__file__), "..", "docs", "_data")
    )


def main(data_dir: str | None = None) -> None:
    data_dir = data_dir or default_data_dir()
    history_file = os.path.join(data_dir, "scan-history.json")
    with open(history_file) as fh:
        history = json.load(fh)

    updated = backfill_history(history, data_dir)

    with open(history_file, "w") as fh:
        json.dump(history, fh, indent=2)
        fh.write("\n")

    print(f"\nUpdated {updated}/{len(history)} entries with profile data")


if __name__ == "__main__":
    main()
