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

### `secrets-consider-external-storage`

**Severity**: MEDIUM

**Why this fails**: Consider external secret storage

Consider the use of an external secrets storage and management system, instead of using Kubernetes Secrets directly, if you have more complex secret management needs. Ensure the solution requires authentication to access secrets, has auditing of access to and use of secrets, and encrypts secrets. Some solutions also make it easier to rotate secrets.

---

### `secrets-no-environment-variables`

**Severity**: MEDIUM

**Why this fails**: Do Not Use Environment Variables with Secrets

Secrets should be mounted as data volumes instead of environment variables.

---

