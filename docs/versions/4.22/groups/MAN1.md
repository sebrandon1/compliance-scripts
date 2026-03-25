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

| Check | Required Action |
|-------|----------------|
| `accounts-restrict-service-account-tokens` | Disable automounting of service account tokens in pods that don't need API access |
| `accounts-unique-service-account` | Use dedicated service accounts per application instead of default |
| `general-apply-scc` | Apply appropriate SecurityContextConstraints to pods and containers |
| `general-configure-imagepolicywebhook` | Configure ImagePolicyWebhook for image provenance verification |
| `general-default-namespace-use` | Don't deploy workloads in the default namespace |
| `general-default-seccomp-profile` | Enable seccomp profiles in pod definitions |
| `general-namespaces-in-use` | Create administrative boundaries using namespaces |
| `scc-drop-container-capabilities` | Drop unnecessary container capabilities |
| `scc-limit-ipc-namespace` | Restrict access to host IPC namespace |
| `scc-limit-net-raw-capability` | Limit use of CAP_NET_RAW capability |
| `scc-limit-network-namespace` | Restrict access to host network namespace |
| `scc-limit-privilege-escalation` | Limit container ability to escalate privileges |
| `scc-limit-privileged-containers` | Limit privileged container use |
| `scc-limit-process-id-namespace` | Restrict access to host PID namespace |
| `scc-limit-root-containers` | Limit containers running as root |

