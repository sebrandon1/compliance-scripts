---
layout: group
group_id: MAN2
version: "4.22"
---

## Overview

These checks require manual review of RBAC policies, role bindings, and access permissions. They ensure the principle of least privilege is followed across the cluster.

**Profile**: CIS, E8, NIST 800-53 Moderate, PCI-DSS

**Type**: Manual — these checks require human review and cannot be automated via MachineConfig or CRD.

## Checks Requiring Manual Action

| Check | Required Action |
|-------|----------------|
| `rbac-least-privilege` | Review all RBAC bindings and ensure least privilege (HIGH severity) |
| `rbac-limit-cluster-admin` | Ensure cluster-admin role is only used where required |
| `rbac-limit-secrets-access` | Restrict access to Kubernetes Secrets |
| `rbac-pod-creation-access` | Minimize who can create pods |
| `rbac-wildcard-use` | Minimize wildcard usage in Cluster and Local Roles |

