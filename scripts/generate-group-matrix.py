#!/usr/bin/env python3
"""Generate group-matrix.json from scan data and tracking remediations.

Cross-references remediation group check names against actual scan results
to produce pass/fail/manual counts per group per OCP version.

Group membership comes from the latest versioned tracking file
(tracking-X_Y.json), so checks added on newer OCP versions appear in the
matrix.
"""

from __future__ import annotations

import glob
import json
import os
import re

VERSIONED_TRACKING_RE = re.compile(r"^tracking-(\d+)_(\d+)\.json$")
VERSIONED_SCAN_RE = re.compile(r"^ocp-\d+_\d+\.json$")

GROUP_DESCRIPTIONS: dict[str, str] = {
    "H1": "Sets the system-wide cryptographic policy to disable weak algorithms like SHA-1, protecting all TLS, SSH, and certificate operations on the node.",
    "H2": "Removes 'nullok' from PAM authentication so that accounts with empty passwords cannot log in to cluster nodes.",
    "H3": "Configures the SSH daemon to reject login attempts using empty passwords.",
    "M1": "Hardens SSH daemon settings: disables root login, GSSAPI, rhosts, user known hosts, user environment, and enables strict mode.",
    "M2": "Applies kernel sysctl parameters to restrict core dumps, disable ICMP redirects, and harden memory protections.",
    "M3": "Adds audit rules to track changes to file permissions and ownership (DAC modifications) so unauthorized access attempts are logged.",
    "M4": "Adds audit rules to log SELinux policy changes and access control modifications on the node.",
    "M5": "Adds audit rules to log loading and unloading of kernel modules, detecting rootkits or unauthorized drivers.",
    "M6": "Adds audit rules to detect attempts to change the system clock, which could be used to tamper with log timestamps.",
    "M7": "Adds audit rules to monitor login events, failed authentication attempts, and account lockouts.",
    "M8": "Adds audit rules to log changes to network configuration files and hostname changes.",
    "M9": "Configures the audit daemon (auditd) with proper hostname identification for centralized log correlation.",
    "M10": "Enables encryption of etcd data at rest using AES-CBC, protecting secrets and sensitive API resources stored in the cluster database.",
    "M11": "Ensures the cluster ingress controller uses strong TLS cipher suites. Passes by default on OCP 4.22+.",
    "M12": "Sets the API server audit profile to WriteRequestBodies, logging the full content of write operations for forensic analysis.",
    "L1": "Sets SSH daemon log level to capture detailed connection and authentication events. Passes by default on RHCOS 9.8+.",
    "L2": "Restricts access to kernel ring buffer messages (dmesg) to root only, preventing information leakage to unprivileged users.",
    "M13": "Extends audit coverage with 11 additional rules for file attribute changes (chmod, chown, fsetxattr, etc.).",
    "M14": "Adds audit watches on 12 identity and authentication files (/etc/passwd, /etc/shadow, /etc/group, etc.) to detect unauthorized modifications.",
    "M15": "Adds audit rules to log file deletion operations (unlink, rename, rmdir) for forensic tracking of removed files.",
    "M16": "Adds audit rules for 32 system calls to log all unsuccessful file modification attempts, catching permission-denied and missing-file errors.",
    "M17": "Adds audit rules to log execution of 22 privileged commands (sudo, chage, mount, etc.) to track administrative actions.",
    "M18": "Adds audit rules for session initiation, MAC policy changes, audit log exports, and makes the audit configuration immutable until reboot.",
    "M19": "Adds audit watches on user/group management files (/etc/passwd, /etc/group, /etc/gshadow, /etc/security/opasswd) to log account changes.",
    "M20": "Configures audit log retention settings: maximum log file size, number of retained logs, and disk-full behavior.",
    "M21": "Blacklists 18 kernel modules (USB storage, Firewire, Bluetooth, uncommon filesystems, etc.) to reduce the node attack surface.",
    "M22": "Applies 20 network sysctl hardening parameters: disables IP forwarding, source routing, ICMP redirects, and enables reverse path filtering.",
    "M23": "Sets kernel parameters to disable core dumps, block kexec_load, and increase perf_event paranoia level.",
    "M24": "Adds 6 kernel boot arguments: enables audit at boot, sets audit backlog limit, disables USB, enables page poisoning, PTI, and disables vsyscall.",
    "M25": "Configures Chrony NTP client to use designated time servers with restricted port access and polling intervals.",
    "M26": "Disables systemd core dump collection, masks the Ctrl-Alt-Del reboot target, and masks the systemd-coredump socket.",
    "M27": "Applies additional SSHD hardening from the Moderate profile: sets ClientAliveInterval and ClientAliveCountMax for idle session timeout.",
    "M28": "Requires USBGuard daemon to control USB device access. Cannot be remediated — USBGuard RPM is not included in RHCOS.",
    "M29": "Mixed group: restricts node-level terminal access (securetty, audit trail) and configures cluster login banner or OAuth templates.",
    "M30": "Configures OAuth access token inactivity timeout and token max age to automatically expire idle sessions.",
    "MAN1": "Manual review items: workload container security — verifying pod security standards, resource limits, and image provenance.",
    "MAN2": "Manual review items: RBAC and access control — verifying least-privilege roles, service accounts, and cluster-admin restrictions.",
    "MAN3": "Manual review items: secrets management — verifying that sensitive data is stored in Secrets resources, not in ConfigMaps or environment variables.",
    "MAN4": "Manual review items: audit log storage — verifying that dedicated partitions or persistent volumes are used for audit log retention.",
    "MAN5": "Manual review items: hardware BIOS settings, alerting rules, and physical security controls that cannot be checked by automated scans.",
}


def default_data_dir() -> str:
    return os.path.normpath(
        os.path.join(os.path.dirname(__file__), "..", "docs", "_data")
    )


def list_matching_json(data_dir: str, name_re: re.Pattern[str]) -> list[str]:
    return sorted(
        path for path in glob.glob(os.path.join(data_dir, "*.json"))
        if name_re.match(os.path.basename(path))
    )


def list_versioned_tracking_files(data_dir: str) -> list[str]:
    return list_matching_json(data_dir, VERSIONED_TRACKING_RE)


def list_scan_files(data_dir: str) -> list[str]:
    return list_matching_json(data_dir, VERSIONED_SCAN_RE)


def tracking_version_key(path: str) -> tuple[int, int]:
    match = VERSIONED_TRACKING_RE.match(os.path.basename(path))
    if not match:
        return (0, 0)
    return (int(match.group(1)), int(match.group(2)))


def latest_tracking_file(paths: list[str]) -> str:
    return max(paths, key=tracking_version_key)


def load_json(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


def load_existing_matrix(path: str) -> dict:
    try:
        return load_json(path)
    except FileNotFoundError:
        return {}


def collect_group_checks(tracking_docs: list[dict]) -> dict[str, set[str]]:
    """Union remediations from tracking documents, keyed by group id."""
    group_checks: dict[str, set[str]] = {}
    for tracking in tracking_docs:
        for check_name, info in tracking.get("remediations", {}).items():
            gid = info.get("group") or ""
            if gid:
                group_checks.setdefault(gid, set()).add(check_name)
    return group_checks


def _check_names(entries: list) -> set[str]:
    names: set[str] = set()
    for entry in entries:
        name = entry.get("check", entry.get("name", ""))
        if name:
            names.add(name)
    return names


def collect_scan_status(scan: dict) -> tuple[set[str], set[str], set[str]]:
    passing: set[str] = set()
    for sev_checks in scan.get("passing_checks", {}).values():
        passing.update(_check_names(sev_checks))
    failing: set[str] = set()
    for sev_checks in scan.get("remediations", {}).values():
        failing.update(_check_names(sev_checks))
    manual = _check_names(scan.get("manual_checks", []))
    return passing, failing, manual


def count_suffix_matches(short_names: set[str], scan_names: set[str]) -> int:
    return sum(
        1 for short in short_names
        if any(sc.endswith(short) for sc in scan_names)
    )


def version_slug_from_scan(path: str) -> str:
    return os.path.basename(path).replace("ocp-", "").replace(".json", "")


def build_matrix(
    group_checks: dict[str, set[str]],
    scans_by_version: dict[str, dict],
    existing: dict | None = None,
    descriptions: dict[str, str] | None = None,
) -> dict[str, dict]:
    existing = existing or {}
    descriptions = (
        descriptions if descriptions is not None else GROUP_DESCRIPTIONS
    )
    matrix: dict[str, dict] = {}

    for vs, scan in scans_by_version.items():
        passing, failing, manual = collect_scan_status(scan)
        for gid, short_names in group_checks.items():
            entry = matrix.setdefault(gid, {})
            entry[vs] = {
                "pass": count_suffix_matches(short_names, passing),
                "fail": count_suffix_matches(short_names, failing),
                "manual": count_suffix_matches(short_names, manual),
                "total": len(short_names),
            }
            if gid in descriptions:
                entry["description"] = descriptions[gid]

    for gid, entry in matrix.items():
        note = existing.get(gid, {}).get("note")
        if note:
            entry["note"] = note

    return matrix


def write_matrix(path: str, matrix: dict) -> None:
    with open(path, "w") as f:
        json.dump(matrix, f, indent=2, sort_keys=True)
        f.write("\n")


def main(data_dir: str | None = None) -> None:
    data_dir = data_dir or default_data_dir()
    tracking_files = list_versioned_tracking_files(data_dir)
    if not tracking_files:
        raise SystemExit(f"No versioned tracking files found in {data_dir}")

    group_checks = collect_group_checks(
        [load_json(latest_tracking_file(tracking_files))]
    )
    scans_by_version = {
        version_slug_from_scan(path): load_json(path)
        for path in list_scan_files(data_dir)
    }
    output = os.path.join(data_dir, "group-matrix.json")
    matrix = build_matrix(
        group_checks,
        scans_by_version,
        existing=load_existing_matrix(output),
    )
    write_matrix(output, matrix)
    print(f"Generated {output} with {len(matrix)} groups")


if __name__ == "__main__":
    main()
