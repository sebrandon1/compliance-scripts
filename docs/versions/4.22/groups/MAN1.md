---
layout: group
group_id: MAN1
version: "4.22"
---

## Overview

These checks require manual review of workload configurations. They cannot be automated via MachineConfig because they depend on application-specific deployments, namespace design, and pod security policies that vary per workload.

**Profile**: CIS, E8, NIST 800-53 Moderate, PCI-DSS

**Type**: Manual — these checks require human review and cannot be automated via MachineConfig or CRD.

## Checks Requiring Manual Action

### `accounts-restrict-service-account-tokens`

**Severity**: MEDIUM

**Why this fails**: Restrict Automounting of Service Account Tokens

Service accounts tokens should not be mounted in pods except where the workload running in the pod explicitly needs to communicate with the API server. To ensure pods do not automatically mount tokens, set automountServiceAccountToken to false.

---

### `accounts-unique-service-account`

**Severity**: MEDIUM

**Why this fails**: Ensure Usage of Unique Service Accounts 

Using the default service account prevents accurate application rights review and audit tracing. Instead of default , create a new and unique service account with the following command:

$ oc create sa service_account_name

where service_account_name is the name of a service account that is needed in the project namespace.

---

### `general-apply-scc`

**Severity**: MEDIUM

**Why this fails**: Apply Security Context to Your Pods and Containers

Apply Security Context to your Pods and Containers

---

### `general-configure-imagepolicywebhook`

**Severity**: MEDIUM

**Why this fails**: Manage Image Provenance Using ImagePolicyWebhook

OpenShift administrators can control which images can be imported, tagged, and run in a cluster. There are two facilities for this purpose: (1) Allowed Registries, allowing administrators to restrict image origins to known external registries; and (2) ImagePolicy Admission plug-in which lets administrators specify specific images which are allowed to run on the OpenShift cluster. Configure an Image policy per the Image Policy chapter in the OpenShift documentation: https://docs.openshift.com/con...

---

### `general-default-namespace-use`

**Severity**: MEDIUM

**Why this fails**: The default namespace should not be used

Kubernetes provides a default namespace, where objects are placed if no namespace is specified for them. Placing objects in this namespace makes application of RBAC and other controls more difficult.

---

### `general-default-seccomp-profile`

**Severity**: MEDIUM

**Why this fails**: Ensure Seccomp Profile Pod Definitions

Enable default seccomp profiles in your pod definitions.

---

### `general-namespaces-in-use`

**Severity**: MEDIUM

**Why this fails**: Create administrative boundaries between resources using namespaces

Use namespaces to isolate your Kubernetes objects.

---

### `scc-drop-container-capabilities`

**Severity**: MEDIUM

**Why this fails**: Drop Container Capabilities

Containers should not enable more capabilities than needed as this opens the door for malicious use. To disable the capabilities, the appropriate Security Context Constraints (SCCs) should set all capabilities as * or a list of capabilities in requiredDropCapabilities.

---

### `scc-limit-ipc-namespace`

**Severity**: MEDIUM

**Why this fails**: Limit Access to the Host IPC Namespace

Containers should not be allowed access to the host's Interprocess Communication (IPC) namespace. To prevent containers from getting access to a host's IPC namespace, the appropriate Security Context Constraints (SCCs) should set allowHostIPC to false.

---

### `scc-limit-net-raw-capability`

**Severity**: MEDIUM

**Why this fails**: Limit Use of the CAP_NET_RAW

Containers should not enable more capabilities than needed as this opens the door for malicious use. CAP_NET_RAW enables a container to launch a network attack on another container or cluster. To disable the CAP_NET_RAW capability, the appropriate Security Context Constraints (SCCs) should set NET_RAW in requiredDropCapabilities.

---

### `scc-limit-network-namespace`

**Severity**: MEDIUM

**Why this fails**: Limit Access to the Host Network Namespace

Containers should not be allowed access to the host's network namespace. To prevent containers from getting access to a host's network namespace, the appropriate Security Context Constraints (SCCs) should set allowHostNetwork to false.

---

### `scc-limit-privilege-escalation`

**Severity**: MEDIUM

**Why this fails**: Limit Containers Ability to Escalate Privileges

Containers should be limited to only the privileges required to run and should not be allowed to escalate their privileges. To prevent containers from escalating privileges, the appropriate Security Context Constraints (SCCs) should set allowPrivilegeEscalation to false.

---

### `scc-limit-privileged-containers`

**Severity**: MEDIUM

**Why this fails**: Limit Privileged Container Use

Containers should be limited to only the privileges required to run. To prevent containers from running as privileged containers, the appropriate Security Context Constraints (SCCs) should set allowPrivilegedContainer to false.

---

### `scc-limit-process-id-namespace`

**Severity**: MEDIUM

**Why this fails**: Limit Access to the Host Process ID Namespace

Containers should not be allowed access to the host's process ID namespace. To prevent containers from getting access to a host's process ID namespace, the appropriate Security Context Constraints (SCCs) should set allowHostPID to false.

---

### `scc-limit-root-containers`

**Severity**: MEDIUM

**Why this fails**: Limit Container Running As Root User

Containers should run as a random non-privileged user. To prevent containers from running as root user, the appropriate Security Context Constraints (SCCs) should set.runAsUser.type to MustRunAsRange.

---

