#!/usr/bin/env python3
"""
Add remediation summaries to compliance JSON data.
Uses pattern matching to generate concise summaries.
"""

import argparse
import json
import os
import re
import tempfile

# Data-driven lookup table: (pattern, summary) tuples checked against
# the lowercased check name using substring matching. Order matters --
# more specific patterns must appear before their generic catch-alls.
SUMMARY_PATTERNS = [
    # Crypto policy
    ("crypto-policy",
     "Set crypto policy: update-crypto-policies --set DEFAULT:NO-SHA1"),
    # Empty passwords
    ("empty-password",
     "Remove 'nullok' from /etc/pam.d/system-auth and password-auth"),
    # Encryption provider
    ("encryption-provider",
     "Set spec.encryption.type to 'aescbc' in apiserver config"),
    # Audit log forwarding
    ("audit-log-forwarding",
     "Configure ClusterLogForwarder for audit log shipping"),
    # Audit profile
    ("audit-profile",
     "Configure API server audit profile in cluster config"),
    # Identity provider
    ("idp-is-configured",
     "Configure OAuth identity provider for authentication"),
    # Ingress TLS ciphers
    ("ingress-controller-tls",
     "Configure strong TLS ciphers in IngressController spec"),
    # kubeadmin removal
    ("kubeadmin-removed",
     "Delete kubeadmin secret: oc delete secret kubeadmin -n kube-system"),
    # Allowed registries (specific before generic)
    ("allowed-registries-for-import",
     "Set spec.allowedRegistriesForImport in image.config.openshift.io"),
    ("allowed-registries",
     "Set spec.registrySources.allowedRegistries in image.config.openshift.io"),
    # Audit rules - DAC modification
    ("audit-rules-dac-modification-chmod",
     "Add audit rule: -a always,exit -S chmod -F auid>=1000 -F key=perm_mod"),
    ("audit-rules-dac-modification-chown",
     "Add audit rule: -a always,exit -S chown -F auid>=1000 -F key=perm_mod"),
    ("audit-rules-dac-modification-fchmod",
     "Add audit rule: -a always,exit -S fchmod -F auid>=1000 -F key=perm_mod"),
    ("audit-rules-dac-modification-fchown",
     "Add audit rule: -a always,exit -S fchown -F auid>=1000 -F key=perm_mod"),
    ("audit-rules-dac-modification-lchown",
     "Add audit rule: -a always,exit -S lchown -F auid>=1000 -F key=perm_mod"),
    ("audit-rules-dac-modification-setxattr",
     "Add audit rule: -a always,exit -S setxattr -F auid>=1000 -F key=perm_mod"),
    ("audit-rules-dac-modification-fremovexattr",
     "Add audit rule: -a always,exit -S fremovexattr -F key=perm_mod"),
    ("audit-rules-dac-modification-fsetxattr",
     "Add audit rule: -a always,exit -S fsetxattr -F key=perm_mod"),
    ("audit-rules-dac-modification-lremovexattr",
     "Add audit rule: -a always,exit -S lremovexattr -F key=perm_mod"),
    ("audit-rules-dac-modification-lsetxattr",
     "Add audit rule: -a always,exit -S lsetxattr -F key=perm_mod"),
    ("audit-rules-dac-modification-removexattr",
     "Add audit rule: -a always,exit -S removexattr -F key=perm_mod"),
    # Audit rules - SELinux execution
    ("audit-rules-execution-chcon",
     "Add audit rule: -a always,exit -F path=/usr/bin/chcon -F key=privileged"),
    ("audit-rules-execution-restorecon",
     "Add audit rule: -a always,exit -F path=/usr/sbin/restorecon"
     " -F key=privileged"),
    ("audit-rules-execution-semanage",
     "Add audit rule: -a always,exit -F path=/usr/sbin/semanage"
     " -F key=privileged"),
    ("audit-rules-execution-setfiles",
     "Add audit rule: -a always,exit -F path=/usr/sbin/setfiles"
     " -F key=privileged"),
    ("audit-rules-execution-setsebool",
     "Add audit rule: -a always,exit -F path=/usr/sbin/setsebool"
     " -F key=privileged"),
    ("audit-rules-execution-seunshare",
     "Add audit rule: -a always,exit -F path=/usr/sbin/seunshare"
     " -F key=privileged"),
    # Audit rules - other categories
    ("audit-rules-login-events",
     "Add audit rules for login events in /etc/audit/rules.d"),
    ("audit-rules-mac-modification",
     "Add audit rule: -w /etc/selinux/ -p wa -k MAC-policy"),
    ("audit-rules-networkconfig",
     "Add audit rules for network configuration changes"),
    ("audit-rules-privileged-commands",
     "Add audit rules for all privileged commands (setuid/setgid)"),
    ("audit-rules-session-events",
     "Add audit rules for session events (utmp, btmp, wtmp)"),
    ("audit-rules-sysadmin-actions",
     "Add audit rule: -w /etc/sudoers -p wa -k actions"),
    ("audit-rules-time",
     "Add audit rules for time-change events"),
    ("audit-rules-usergroup",
     "Add audit rules for user/group modification events"),
    # Audit rules - generic catch-all (must be after specific rules)
    ("audit-rules",
     "Configure audit rules in /etc/audit/rules.d"),
    # SSHD settings (specific before generic)
    ("sshd-disable-empty-passwords",
     "Set PermitEmptyPasswords no in sshd_config"),
    ("sshd-disable-gssapi",
     "Set GSSAPIAuthentication no in sshd_config"),
    ("sshd-disable-rhosts",
     "Set IgnoreRhosts yes in sshd_config"),
    ("sshd-disable-root-login",
     "Set PermitRootLogin no in sshd_config"),
    ("sshd-disable-user-known-hosts",
     "Set IgnoreUserKnownHosts yes in sshd_config"),
    ("sshd-do-not-permit-user-env",
     "Set PermitUserEnvironment no in sshd_config"),
    ("sshd-enable-strictmodes",
     "Set StrictModes yes in sshd_config"),
    ("sshd-print-last-log",
     "Set PrintLastLog yes in sshd_config"),
    ("sshd-set-idle-timeout",
     "Set ClientAliveInterval 600 in sshd_config"),
    ("sshd-set-keepalive",
     "Set ClientAliveCountMax 0 in sshd_config"),
    ("sshd-use-priv-separation",
     "Set UsePrivilegeSeparation sandbox in sshd_config"),
    # SSHD - generic catch-all (must be after specific sshd rules)
    ("sshd",
     "Configure sshd_config security settings"),
    # Sysctl settings (specific before generic catch-all handled below)
    ("sysctl-kernel-dmesg-restrict",
     "Set kernel.dmesg_restrict=1 via sysctl"),
    ("sysctl-kernel-kexec-load-disabled",
     "Set kernel.kexec_load_disabled=1 via sysctl"),
    ("sysctl-kernel-kptr-restrict",
     "Set kernel.kptr_restrict=1 via sysctl"),
    ("sysctl-kernel-perf-event-paranoid",
     "Set kernel.perf_event_paranoid=2 via sysctl"),
    ("sysctl-kernel-unprivileged-bpf-disabled",
     "Set kernel.unprivileged_bpf_disabled=1 via sysctl"),
    ("sysctl-kernel-yama-ptrace-scope",
     "Set kernel.yama.ptrace_scope=1 via sysctl"),
    ("sysctl-net-core-bpf-jit-harden",
     "Set net.core.bpf_jit_harden=2 via sysctl"),
    ("sysctl-net-ipv4-conf-all-accept-redirects",
     "Set net.ipv4.conf.all.accept_redirects=0 via sysctl"),
    ("sysctl-net-ipv4-conf-all-accept-source-route",
     "Set net.ipv4.conf.all.accept_source_route=0 via sysctl"),
    ("sysctl-net-ipv4-conf-all-log-martians",
     "Set net.ipv4.conf.all.log_martians=1 via sysctl"),
    ("sysctl-net-ipv4-conf-all-rp-filter",
     "Set net.ipv4.conf.all.rp_filter=1 via sysctl"),
    ("sysctl-net-ipv4-conf-all-secure-redirects",
     "Set net.ipv4.conf.all.secure_redirects=0 via sysctl"),
    ("sysctl-net-ipv4-conf-all-send-redirects",
     "Set net.ipv4.conf.all.send_redirects=0 via sysctl"),
    ("sysctl-net-ipv4-conf-default-accept-redirects",
     "Set net.ipv4.conf.default.accept_redirects=0 via sysctl"),
    ("sysctl-net-ipv4-conf-default-accept-source-route",
     "Set net.ipv4.conf.default.accept_source_route=0 via sysctl"),
    ("sysctl-net-ipv4-conf-default-log-martians",
     "Set net.ipv4.conf.default.log_martians=1 via sysctl"),
    ("sysctl-net-ipv4-conf-default-rp-filter",
     "Set net.ipv4.conf.default.rp_filter=1 via sysctl"),
    ("sysctl-net-ipv4-conf-default-secure-redirects",
     "Set net.ipv4.conf.default.secure_redirects=0 via sysctl"),
    ("sysctl-net-ipv4-conf-default-send-redirects",
     "Set net.ipv4.conf.default.send_redirects=0 via sysctl"),
    ("sysctl-net-ipv4-icmp-echo-ignore-broadcasts",
     "Set net.ipv4.icmp_echo_ignore_broadcasts=1 via sysctl"),
    ("sysctl-net-ipv4-icmp-ignore-bogus-error-responses",
     "Set net.ipv4.icmp_ignore_bogus_error_responses=1 via sysctl"),
    ("sysctl-net-ipv4-ip-forward",
     "Set net.ipv4.ip_forward=0 via sysctl"),
    ("sysctl-net-ipv4-tcp-syncookies",
     "Set net.ipv4.tcp_syncookies=1 via sysctl"),
    ("sysctl-net-ipv6-conf-all-accept-ra",
     "Set net.ipv6.conf.all.accept_ra=0 via sysctl"),
    ("sysctl-net-ipv6-conf-all-accept-redirects",
     "Set net.ipv6.conf.all.accept_redirects=0 via sysctl"),
    ("sysctl-net-ipv6-conf-all-accept-source-route",
     "Set net.ipv6.conf.all.accept_source_route=0 via sysctl"),
    ("sysctl-net-ipv6-conf-all-forwarding",
     "Set net.ipv6.conf.all.forwarding=0 via sysctl"),
    ("sysctl-net-ipv6-conf-default-accept-ra",
     "Set net.ipv6.conf.default.accept_ra=0 via sysctl"),
    ("sysctl-net-ipv6-conf-default-accept-redirects",
     "Set net.ipv6.conf.default.accept_redirects=0 via sysctl"),
    ("sysctl-net-ipv6-conf-default-accept-source-route",
     "Set net.ipv6.conf.default.accept_source_route=0 via sysctl"),
    # Service account tokens
    ("service-account-tokens",
     "Set automountServiceAccountToken: false in pod specs"),
    # RBAC (specific before generic)
    ("rbac-limit-cluster-admin",
     "Review and limit cluster-admin role assignments"),
    ("rbac-limit-secrets",
     "Restrict RBAC access to secrets"),
    ("rbac-wildcard",
     "Avoid wildcard (*) in RBAC rules"),
    ("rbac",
     "Review and restrict RBAC permissions"),
    # SCCs (specific before generic)
    ("scc-limit-container-capabilities",
     "Configure SCCs to drop unnecessary capabilities"),
    ("scc-limit-root",
     "Configure SCCs to prevent root containers"),
    ("scc-limit-privileged",
     "Configure SCCs to restrict privileged containers"),
    ("scc-limit-process-id",
     "Configure SCCs with hostPID: false"),
    ("scc-limit-ipc",
     "Configure SCCs with hostIPC: false"),
    ("scc-limit-network",
     "Configure SCCs with hostNetwork: false"),
    ("scc-limit-host-dir-volume",
     "Configure SCCs to restrict hostPath volumes"),
    ("scc-drop-capabilities",
     "Configure SCCs to drop container capabilities"),
    ("scc",
     "Configure SecurityContextConstraints appropriately"),
    # File permissions
    ("file-permissions",
     "Set appropriate file permissions and ownership"),
    ("file-owner",
     "Set appropriate file permissions and ownership"),
    # Coredump
    ("coredump-disable",
     "Set Storage=none in /etc/systemd/coredump.conf"),
]


def generate_summary(name: str, description: str) -> str:
    """Generate a concise remediation summary based on the check name and description."""
    if not description:
        return ""

    desc_lower = description.lower()
    name_lower = name.lower()

    # Network policies (checks both name and description)
    if "network-policies" in name_lower or "networkpolicy" in desc_lower:
        return "Add NetworkPolicy to each namespace"

    # Check name-based patterns from the lookup table
    for pattern, summary in SUMMARY_PATTERNS:
        if pattern in name_lower:
            return summary

    # Sysctl catch-all: extract the parameter name from unrecognized sysctl checks
    if "sysctl" in name_lower:
        match = re.search(r'sysctl-(.+)', name_lower)
        if match:
            param = match.group(1).replace('-', '.')
            return f"Configure {param} via sysctl"
        return "Configure kernel sysctl parameter"

    # Default fallback - try to extract action from description
    if "create a machineconfig" in desc_lower:
        return "Apply MachineConfig to configure this setting"
    if "set " in desc_lower[:100].lower():
        # Try to extract the setting
        match = re.search(
            r'set\s+(\S+)\s+(?:to\s+)?(\S+)', description[:200],
            re.IGNORECASE
        )
        if match:
            return f"Set {match.group(1)} to {match.group(2)}"

    return "Review and apply recommended configuration"


def process_checks(checks: list) -> int:
    """Add summaries to checks, return count of summaries added."""
    count = 0
    for check in checks:
        if not check.get("summary"):
            summary = generate_summary(check.get("name", ""), check.get("description", ""))
            if summary:
                check["summary"] = summary
                count += 1
                print(f"  {check.get('name')}: {summary}")
    return count


def main():
    parser = argparse.ArgumentParser(
        description="Add human-readable summaries to compliance check data"
    )
    parser.add_argument(
        "json_file",
        help="Path to the compliance JSON file to enrich with summaries"
    )
    args = parser.parse_args()

    json_file = args.json_file

    print(f"Loading {json_file}...")
    with open(json_file, 'r') as f:
        data = json.load(f)

    total = 0

    print("\nProcessing HIGH severity checks...")
    if data.get("remediations", {}).get("high"):
        total += process_checks(data["remediations"]["high"])

    print("\nProcessing MEDIUM severity checks...")
    if data.get("remediations", {}).get("medium"):
        total += process_checks(data["remediations"]["medium"])

    print("\nProcessing LOW severity checks...")
    if data.get("remediations", {}).get("low"):
        total += process_checks(data["remediations"]["low"])

    print("\nProcessing MANUAL checks...")
    if data.get("manual_checks"):
        total += process_checks(data["manual_checks"])

    print("\nProcessing PASSING HIGH checks...")
    if data.get("passing_checks", {}).get("high"):
        total += process_checks(data["passing_checks"]["high"])

    print("\nProcessing PASSING MEDIUM checks...")
    if data.get("passing_checks", {}).get("medium"):
        total += process_checks(data["passing_checks"]["medium"])

    print("\nProcessing PASSING LOW checks...")
    if data.get("passing_checks", {}).get("low"):
        total += process_checks(data["passing_checks"]["low"])

    print(f"\nWriting {total} summaries to {json_file}...")
    tmp_fd, tmp_path = tempfile.mkstemp(
        suffix='.json', dir=os.path.dirname(os.path.abspath(json_file))
    )
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            json.dump(data, f, indent=2)
        os.replace(tmp_path, json_file)
    except BaseException:
        os.unlink(tmp_path)
        raise

    print("Done!")


if __name__ == "__main__":
    main()
