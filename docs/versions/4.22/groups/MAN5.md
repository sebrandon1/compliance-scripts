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

### `bios-disable-usb-boot`

**Severity**: UNKNOWN

**Why this fails**: Disable Booting from USB Devices in Boot Firmware

Configure the system boot firmware (historically called BIOS on PC systems) to disallow booting from USB drives.

---

### `wireless-disable-in-bios`

**Severity**: UNKNOWN

**Why this fails**: Disable WiFi or Bluetooth in BIOS

Some machines that include built-in wireless support offer the ability to disable the device through the BIOS. This is hardware-specific; consult your hardware manual or explore the BIOS setup during boot.

---

### `alert-receiver-configured`

**Severity**: MEDIUM

**Why this fails**: Ensure the alert receiver is configured

In OpenShift Container Platform, an alert is fired when the conditions defined in an alerting rule are true. An alert provides a notification that a set of circumstances are apparent within a cluster. Firing alerts can be viewed in the Alerting UI in the OpenShift Container Platform web console by default. After an installation, you can configure OpenShift Container Platform to send alert notifications to external systems so that designate personnel can be alerted in real time. OpenShift provide...

---

