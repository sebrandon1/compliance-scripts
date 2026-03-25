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

| Check | Required Action |
|-------|----------------|
| `partition-for-var-log (master)` | Ensure /var/log is on a separate partition (master nodes) |
| `partition-for-var-log (worker)` | Ensure /var/log is on a separate partition (worker nodes) |
| `partition-for-var-log-audit (master)` | Ensure /var/log/audit is on a separate partition (master nodes) |
| `partition-for-var-log-audit (worker)` | Ensure /var/log/audit is on a separate partition (worker nodes) |

