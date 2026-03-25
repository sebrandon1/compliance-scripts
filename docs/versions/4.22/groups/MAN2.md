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

### `rbac-least-privilege`

**Severity**: HIGH

**Why this fails**: Ensure that the RBAC setup follows the principle of least privilege

Role-based access control (RBAC) objects determine whether a user is allowed to perform a given action within a project. If users or groups exist that are bound to roles they must not have, modify the user or group permissions using the following cluster and local role binding commands: Remove a User from a Cluster RBAC role by executing the following: oc adm policy remove-cluster-role-from-user role username Remove a Group from a Cluster RBAC role by executing the following: oc adm policy remov...

---

### `rbac-limit-cluster-admin`

**Severity**: MEDIUM

**Why this fails**: Ensure that the cluster-admin role is only used where required

The RBAC role cluster-admin provides wide-ranging powers over the environment and should be used only where and when needed.

---

### `rbac-limit-secrets-access`

**Severity**: MEDIUM

**Why this fails**: Limit Access to Kubernetes Secrets

The Kubernetes API stores secrets, which may be service account tokens for the Kubernetes API or credentials used by workloads in the cluster. Access to these secrets should be restricted to the smallest possible group of users to reduce the risk of privilege escalation. To restrict users from secrets, remove get , list , and watch access to unauthorized users to secret objects in the cluster.

---

### `rbac-pod-creation-access`

**Severity**: MEDIUM

**Why this fails**: Minimize Access to Pod Creation

The ability to create pods in a namespace can provide a number of opportunities for privilege escalation. Where applicable, remove create access to pod objects in the cluster.

---

### `rbac-wildcard-use`

**Severity**: MEDIUM

**Why this fails**: Minimize Wildcard Usage in Cluster and Local Roles

Kubernetes Cluster and Local Roles provide access to resources based on sets of objects and actions that can be taken on those objects. It is possible to set either of these using a wildcard * which matches all items. This violates the principle of least privilege and leaves a cluster in a more vulnerable state to privilege abuse.

---

