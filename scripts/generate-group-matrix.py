#!/usr/bin/env python3
"""Generate group-matrix.json from scan data and tracking remediations.

Cross-references remediation group check names against actual scan results
to produce pass/fail/manual counts per group per OCP version.
"""

import glob
import json
import os

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

    matrix: dict[str, dict[str, object]] = {}

    existing_file = os.path.join(data_dir, "group-matrix.json")
    existing: dict[str, dict] = {}
    if os.path.exists(existing_file):
        with open(existing_file) as f:
            existing = json.load(f)

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

            entry = matrix.setdefault(gid, {})
            entry[vs] = {
                "pass": pass_count,
                "fail": fail_count,
                "manual": manual_count,
                "total": len(short_names),
            }
            if gid in GROUP_DESCRIPTIONS:
                entry["description"] = GROUP_DESCRIPTIONS[gid]

    for gid in matrix:
        if gid in existing and "note" in existing[gid]:
            matrix[gid]["note"] = existing[gid]["note"]

    output = os.path.join(data_dir, "group-matrix.json")
    with open(output, "w") as f:
        json.dump(matrix, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"Generated {output} with {len(matrix)} groups")


if __name__ == "__main__":
    main()
