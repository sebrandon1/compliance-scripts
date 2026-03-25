---
layout: group
group_id: MAN5
version: "4.22"
---

## Overview

These checks require physical or BIOS-level configuration changes that cannot be applied via software. They also include alerting infrastructure that depends on external systems.

**Profile**: NIST 800-53 Moderate, PCI-DSS

**Type**: Manual — these checks require human review and cannot be automated via MachineConfig or CRD.

## Checks Requiring Manual Action

| Check | Required Action |
|-------|----------------|
| `bios-disable-usb-boot (master)` | Disable booting from USB devices in BIOS firmware (master nodes) |
| `bios-disable-usb-boot (worker)` | Disable booting from USB devices in BIOS firmware (worker nodes) |
| `wireless-disable-in-bios (master)` | Disable WiFi/Bluetooth in BIOS (master nodes) |
| `wireless-disable-in-bios (worker)` | Disable WiFi/Bluetooth in BIOS (worker nodes) |
| `alert-receiver-configured` | Configure an alert receiver for the OpenShift monitoring stack |

