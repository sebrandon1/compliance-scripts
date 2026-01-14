#!/usr/bin/env python3
"""
Add remediation summaries to compliance JSON data.
Uses pattern matching to generate concise summaries.
"""

import json
import re
import sys


def generate_summary(name: str, description: str) -> str:
    """Generate a concise remediation summary based on the check name and description."""
    if not description:
        return ""

    desc_lower = description.lower()
    name_lower = name.lower()

    # Network policies
    if "network-policies" in name_lower or "networkpolicy" in desc_lower:
        return "Add NetworkPolicy to each namespace"

    # Crypto policy
    if "crypto-policy" in name_lower:
        return "Set crypto policy: update-crypto-policies --set DEFAULT:NO-SHA1"

    # Empty passwords
    if "empty-password" in name_lower or "no-empty-passwords" in name_lower:
        return "Remove 'nullok' from /etc/pam.d/system-auth and password-auth"

    # Encryption provider
    if "encryption-provider" in name_lower:
        return "Set spec.encryption.type to 'aescbc' in apiserver config"

    # Audit log forwarding
    if "audit-log-forwarding" in name_lower:
        return "Configure ClusterLogForwarder for audit log shipping"

    # Audit profile
    if "audit-profile" in name_lower:
        return "Configure API server audit profile in cluster config"

    # Identity provider
    if "idp-is-configured" in name_lower:
        return "Configure OAuth identity provider for authentication"

    # Ingress TLS ciphers
    if "ingress-controller-tls" in name_lower:
        return "Configure strong TLS ciphers in IngressController spec"

    # kubeadmin removal
    if "kubeadmin-removed" in name_lower:
        return "Delete kubeadmin secret: oc delete secret kubeadmin -n kube-system"

    # Allowed registries
    if "allowed-registries-for-import" in name_lower:
        return "Set spec.allowedRegistriesForImport in image.config.openshift.io"
    if "allowed-registries" in name_lower:
        return "Set spec.registrySources.allowedRegistries in image.config.openshift.io"

    # Audit rules
    if "audit-rules-dac-modification-chmod" in name_lower:
        return "Add audit rule: -a always,exit -S chmod -F auid>=1000 -F key=perm_mod"
    if "audit-rules-dac-modification-chown" in name_lower:
        return "Add audit rule: -a always,exit -S chown -F auid>=1000 -F key=perm_mod"
    if "audit-rules-dac-modification-fchmod" in name_lower:
        return "Add audit rule: -a always,exit -S fchmod -F auid>=1000 -F key=perm_mod"
    if "audit-rules-dac-modification-fchown" in name_lower:
        return "Add audit rule: -a always,exit -S fchown -F auid>=1000 -F key=perm_mod"
    if "audit-rules-dac-modification-lchown" in name_lower:
        return "Add audit rule: -a always,exit -S lchown -F auid>=1000 -F key=perm_mod"
    if "audit-rules-dac-modification-setxattr" in name_lower:
        return "Add audit rule: -a always,exit -S setxattr -F auid>=1000 -F key=perm_mod"
    if "audit-rules-dac-modification-fremovexattr" in name_lower:
        return "Add audit rule: -a always,exit -S fremovexattr -F key=perm_mod"
    if "audit-rules-dac-modification-fsetxattr" in name_lower:
        return "Add audit rule: -a always,exit -S fsetxattr -F key=perm_mod"
    if "audit-rules-dac-modification-lremovexattr" in name_lower:
        return "Add audit rule: -a always,exit -S lremovexattr -F key=perm_mod"
    if "audit-rules-dac-modification-lsetxattr" in name_lower:
        return "Add audit rule: -a always,exit -S lsetxattr -F key=perm_mod"
    if "audit-rules-dac-modification-removexattr" in name_lower:
        return "Add audit rule: -a always,exit -S removexattr -F key=perm_mod"
    if "audit-rules-execution-chcon" in name_lower:
        return "Add audit rule: -a always,exit -F path=/usr/bin/chcon -F key=privileged"
    if "audit-rules-execution-restorecon" in name_lower:
        return "Add audit rule: -a always,exit -F path=/usr/sbin/restorecon -F key=privileged"
    if "audit-rules-execution-semanage" in name_lower:
        return "Add audit rule: -a always,exit -F path=/usr/sbin/semanage -F key=privileged"
    if "audit-rules-execution-setfiles" in name_lower:
        return "Add audit rule: -a always,exit -F path=/usr/sbin/setfiles -F key=privileged"
    if "audit-rules-execution-setsebool" in name_lower:
        return "Add audit rule: -a always,exit -F path=/usr/sbin/setsebool -F key=privileged"
    if "audit-rules-execution-seunshare" in name_lower:
        return "Add audit rule: -a always,exit -F path=/usr/sbin/seunshare -F key=privileged"
    if "audit-rules-login-events" in name_lower:
        return "Add audit rules for login events in /etc/audit/rules.d"
    if "audit-rules-mac-modification" in name_lower:
        return "Add audit rule: -w /etc/selinux/ -p wa -k MAC-policy"
    if "audit-rules-networkconfig" in name_lower:
        return "Add audit rules for network configuration changes"
    if "audit-rules-privileged-commands" in name_lower:
        return "Add audit rules for all privileged commands (setuid/setgid)"
    if "audit-rules-session-events" in name_lower:
        return "Add audit rules for session events (utmp, btmp, wtmp)"
    if "audit-rules-sysadmin-actions" in name_lower:
        return "Add audit rule: -w /etc/sudoers -p wa -k actions"
    if "audit-rules-time" in name_lower:
        return "Add audit rules for time-change events"
    if "audit-rules-usergroup" in name_lower:
        return "Add audit rules for user/group modification events"
    if "audit-rules" in name_lower:
        return "Configure audit rules in /etc/audit/rules.d"

    # SSHD settings
    if "sshd-disable-empty-passwords" in name_lower:
        return "Set PermitEmptyPasswords no in sshd_config"
    if "sshd-disable-gssapi" in name_lower:
        return "Set GSSAPIAuthentication no in sshd_config"
    if "sshd-disable-rhosts" in name_lower:
        return "Set IgnoreRhosts yes in sshd_config"
    if "sshd-disable-root-login" in name_lower:
        return "Set PermitRootLogin no in sshd_config"
    if "sshd-disable-user-known-hosts" in name_lower:
        return "Set IgnoreUserKnownHosts yes in sshd_config"
    if "sshd-do-not-permit-user-env" in name_lower:
        return "Set PermitUserEnvironment no in sshd_config"
    if "sshd-enable-strictmodes" in name_lower:
        return "Set StrictModes yes in sshd_config"
    if "sshd-print-last-log" in name_lower:
        return "Set PrintLastLog yes in sshd_config"
    if "sshd-set-idle-timeout" in name_lower:
        return "Set ClientAliveInterval 600 in sshd_config"
    if "sshd-set-keepalive" in name_lower:
        return "Set ClientAliveCountMax 0 in sshd_config"
    if "sshd-use-priv-separation" in name_lower:
        return "Set UsePrivilegeSeparation sandbox in sshd_config"
    if "sshd" in name_lower:
        return "Configure sshd_config security settings"

    # Sysctl settings
    if "sysctl-kernel-dmesg-restrict" in name_lower:
        return "Set kernel.dmesg_restrict=1 via sysctl"
    if "sysctl-kernel-kexec-load-disabled" in name_lower:
        return "Set kernel.kexec_load_disabled=1 via sysctl"
    if "sysctl-kernel-kptr-restrict" in name_lower:
        return "Set kernel.kptr_restrict=1 via sysctl"
    if "sysctl-kernel-perf-event-paranoid" in name_lower:
        return "Set kernel.perf_event_paranoid=2 via sysctl"
    if "sysctl-kernel-unprivileged-bpf-disabled" in name_lower:
        return "Set kernel.unprivileged_bpf_disabled=1 via sysctl"
    if "sysctl-kernel-yama-ptrace-scope" in name_lower:
        return "Set kernel.yama.ptrace_scope=1 via sysctl"
    if "sysctl-net-core-bpf-jit-harden" in name_lower:
        return "Set net.core.bpf_jit_harden=2 via sysctl"
    if "sysctl-net-ipv4-conf-all-accept-redirects" in name_lower:
        return "Set net.ipv4.conf.all.accept_redirects=0 via sysctl"
    if "sysctl-net-ipv4-conf-all-accept-source-route" in name_lower:
        return "Set net.ipv4.conf.all.accept_source_route=0 via sysctl"
    if "sysctl-net-ipv4-conf-all-log-martians" in name_lower:
        return "Set net.ipv4.conf.all.log_martians=1 via sysctl"
    if "sysctl-net-ipv4-conf-all-rp-filter" in name_lower:
        return "Set net.ipv4.conf.all.rp_filter=1 via sysctl"
    if "sysctl-net-ipv4-conf-all-secure-redirects" in name_lower:
        return "Set net.ipv4.conf.all.secure_redirects=0 via sysctl"
    if "sysctl-net-ipv4-conf-all-send-redirects" in name_lower:
        return "Set net.ipv4.conf.all.send_redirects=0 via sysctl"
    if "sysctl-net-ipv4-conf-default-accept-redirects" in name_lower:
        return "Set net.ipv4.conf.default.accept_redirects=0 via sysctl"
    if "sysctl-net-ipv4-conf-default-accept-source-route" in name_lower:
        return "Set net.ipv4.conf.default.accept_source_route=0 via sysctl"
    if "sysctl-net-ipv4-conf-default-log-martians" in name_lower:
        return "Set net.ipv4.conf.default.log_martians=1 via sysctl"
    if "sysctl-net-ipv4-conf-default-rp-filter" in name_lower:
        return "Set net.ipv4.conf.default.rp_filter=1 via sysctl"
    if "sysctl-net-ipv4-conf-default-secure-redirects" in name_lower:
        return "Set net.ipv4.conf.default.secure_redirects=0 via sysctl"
    if "sysctl-net-ipv4-conf-default-send-redirects" in name_lower:
        return "Set net.ipv4.conf.default.send_redirects=0 via sysctl"
    if "sysctl-net-ipv4-icmp-echo-ignore-broadcasts" in name_lower:
        return "Set net.ipv4.icmp_echo_ignore_broadcasts=1 via sysctl"
    if "sysctl-net-ipv4-icmp-ignore-bogus-error-responses" in name_lower:
        return "Set net.ipv4.icmp_ignore_bogus_error_responses=1 via sysctl"
    if "sysctl-net-ipv4-ip-forward" in name_lower:
        return "Set net.ipv4.ip_forward=0 via sysctl"
    if "sysctl-net-ipv4-tcp-syncookies" in name_lower:
        return "Set net.ipv4.tcp_syncookies=1 via sysctl"
    if "sysctl-net-ipv6-conf-all-accept-ra" in name_lower:
        return "Set net.ipv6.conf.all.accept_ra=0 via sysctl"
    if "sysctl-net-ipv6-conf-all-accept-redirects" in name_lower:
        return "Set net.ipv6.conf.all.accept_redirects=0 via sysctl"
    if "sysctl-net-ipv6-conf-all-accept-source-route" in name_lower:
        return "Set net.ipv6.conf.all.accept_source_route=0 via sysctl"
    if "sysctl-net-ipv6-conf-all-forwarding" in name_lower:
        return "Set net.ipv6.conf.all.forwarding=0 via sysctl"
    if "sysctl-net-ipv6-conf-default-accept-ra" in name_lower:
        return "Set net.ipv6.conf.default.accept_ra=0 via sysctl"
    if "sysctl-net-ipv6-conf-default-accept-redirects" in name_lower:
        return "Set net.ipv6.conf.default.accept_redirects=0 via sysctl"
    if "sysctl-net-ipv6-conf-default-accept-source-route" in name_lower:
        return "Set net.ipv6.conf.default.accept_source_route=0 via sysctl"
    if "sysctl" in name_lower:
        # Extract the sysctl parameter from the name
        match = re.search(r'sysctl-(.+)', name_lower)
        if match:
            param = match.group(1).replace('-', '.')
            return f"Configure {param} via sysctl"
        return "Configure kernel sysctl parameter"

    # Service account tokens
    if "service-account-tokens" in name_lower:
        return "Set automountServiceAccountToken: false in pod specs"

    # RBAC
    if "rbac-limit-cluster-admin" in name_lower:
        return "Review and limit cluster-admin role assignments"
    if "rbac-limit-secrets" in name_lower:
        return "Restrict RBAC access to secrets"
    if "rbac-wildcard" in name_lower:
        return "Avoid wildcard (*) in RBAC rules"
    if "rbac" in name_lower:
        return "Review and restrict RBAC permissions"

    # SCCs
    if "scc-limit-container-capabilities" in name_lower:
        return "Configure SCCs to drop unnecessary capabilities"
    if "scc-limit-root" in name_lower:
        return "Configure SCCs to prevent root containers"
    if "scc-limit-privileged" in name_lower:
        return "Configure SCCs to restrict privileged containers"
    if "scc-limit-process-id" in name_lower:
        return "Configure SCCs with hostPID: false"
    if "scc-limit-ipc" in name_lower:
        return "Configure SCCs with hostIPC: false"
    if "scc-limit-network" in name_lower:
        return "Configure SCCs with hostNetwork: false"
    if "scc-limit-host-dir-volume" in name_lower:
        return "Configure SCCs to restrict hostPath volumes"
    if "scc-drop-capabilities" in name_lower:
        return "Configure SCCs to drop container capabilities"
    if "scc" in name_lower:
        return "Configure SecurityContextConstraints appropriately"

    # File permissions
    if "file-permissions" in name_lower or "file-owner" in name_lower:
        return "Set appropriate file permissions and ownership"

    # Coredump
    if "coredump-disable" in name_lower:
        return "Set Storage=none in /etc/systemd/coredump.conf"

    # Default fallback - try to extract action from description
    if "create a machineconfig" in desc_lower:
        return "Apply MachineConfig to configure this setting"
    if "set " in desc_lower[:100].lower():
        # Try to extract the setting
        match = re.search(r'set\s+(\S+)\s+(?:to\s+)?(\S+)', description[:200], re.IGNORECASE)
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
    if len(sys.argv) < 2:
        print("Usage: ./add-summaries.py <json-file>", file=sys.stderr)
        sys.exit(1)

    json_file = sys.argv[1]

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

    print(f"\nWriting {total} summaries to {json_file}...")
    with open(json_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("Done!")


if __name__ == "__main__":
    main()
