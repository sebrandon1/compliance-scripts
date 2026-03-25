---
layout: group
group_id: MAN3
version: "4.22"
---

## Overview

These checks require reviewing how secrets are stored and consumed. They recommend using external secret management and avoiding environment variables for sensitive data.

**Profile**: CIS, NIST 800-53 Moderate, PCI-DSS

**Type**: Manual — these checks require human review and cannot be automated via MachineConfig or CRD.

## Checks Requiring Manual Action

| Check | Required Action |
|-------|----------------|
| `secrets-consider-external-storage` | Consider using an external secrets management system (e.g., Vault) |
| `secrets-no-environment-variables` | Mount secrets as volumes instead of passing via environment variables |

