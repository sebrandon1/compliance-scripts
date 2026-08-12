#!/usr/bin/env python3
"""Generate group-matrix.json from scan data and tracking remediations.

Cross-references remediation group check names against actual scan results
to produce pass/fail/manual counts per group per OCP version.
"""

import glob
import json
import os


def main() -> None:
    data_dir = os.path.join(os.path.dirname(__file__), "..", "docs", "_data")
    data_dir = os.path.normpath(data_dir)

    tracking_file = os.path.join(data_dir, "tracking-4_22.json")
    with open(tracking_file) as f:
        tracking = json.load(f)

    group_checks: dict[str, set[str]] = {}
    for check_name, info in tracking["remediations"].items():
        gid = info.get("group", "")
        if gid:
            group_checks.setdefault(gid, set()).add(check_name)

    scan_files = sorted(glob.glob(os.path.join(data_dir, "ocp-[0-9]_[0-9]*.json")))
    scan_files = [
        f
        for f in scan_files
        if not os.path.basename(f).count("-") > 1  # skip timestamped baselines
    ]

    matrix: dict[str, dict[str, dict[str, int]]] = {}

    for scan_file in scan_files:
        basename = os.path.basename(scan_file)
        vs = basename.replace("ocp-", "").replace(".json", "")

        with open(scan_file) as f:
            scan = json.load(f)

        all_passing: set[str] = set()
        for sev_checks in scan.get("passing_checks", {}).values():
            for c in sev_checks:
                all_passing.add(c.get("check", c.get("name", "")))

        all_failing: set[str] = set()
        for sev_checks in scan.get("remediations", {}).values():
            for c in sev_checks:
                all_failing.add(c.get("check", c.get("name", "")))

        all_manual: set[str] = set()
        for c in scan.get("manual_checks", []):
            all_manual.add(c.get("check", c.get("name", "")))

        for gid, short_names in group_checks.items():
            pass_count = 0
            fail_count = 0
            manual_count = 0
            for short in short_names:
                if any(sc.endswith(short) for sc in all_passing):
                    pass_count += 1
                if any(sc.endswith(short) for sc in all_failing):
                    fail_count += 1
                if any(sc.endswith(short) for sc in all_manual):
                    manual_count += 1

            matrix.setdefault(gid, {})[vs] = {
                "pass": pass_count,
                "fail": fail_count,
                "manual": manual_count,
                "total": len(short_names),
            }

    output = os.path.join(data_dir, "group-matrix.json")
    with open(output, "w") as f:
        json.dump(matrix, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"Generated {output} with {len(matrix)} groups")


if __name__ == "__main__":
    main()
