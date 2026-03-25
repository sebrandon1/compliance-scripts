---
layout: group
group_id: MAN4
version: "4.22"
---

## Overview

These checks recommend placing audit and system logs on separate disk partitions to prevent log data from filling the root filesystem. This is a node provisioning decision that must be made at install time.

**Profile**: NIST 800-53 Moderate (`rhcos4-moderate`)

**Type**: Manual — these checks require human review and cannot be automated via MachineConfig or CRD.

## Checks Requiring Manual Action

### `partition-for-var-log`

**Severity**: LOW

**Why this fails**: Ensure /var/log Located On Separate Partition

System logs are stored in the /var/log directory.

Partitioning Red Hat CoreOS is a Day 1 operation and cannot be changed afterwards. For documentation on how to add a MachineConfig manifest that specifies a separate /var/log partition, follow: https://docs.openshift.com/container-platform/latest/installing/installing_platform_agnostic/installing-platform-agnostic.html#installation-user-infra-machines-advanced_disk_installing-platform-agnostic

Note that the Red Hat OpenShift documentation often...

---

### `partition-for-var-log-audit`

**Severity**: LOW

**Why this fails**: Ensure /var/log/audit Located On Separate Partition

Audit logs are stored in the /var/log/audit directory.

Partitioning Red Hat CoreOS is a Day 1 operation and cannot be changed afterwards. For documentation on how to add a MachineConfig manifest that specifies a separate /var/log/audit partition, follow: https://docs.openshift.com/container-platform/latest/installing/installing_platform_agnostic/installing-platform-agnostic.html#installation-user-infra-machines-advanced_disk_installing-platform-agnostic

Note that the Red Hat OpenShift document...

---

