# Verify Remediation Group on Cluster

Apply a group's MachineConfig to a live OCP cluster, wait for rollout, and verify the settings are active.

## Inputs

The user provides:
- Group ID (e.g., M1, M4, M26)
- OCP version (e.g., 4.22) — defaults to latest version in `docs/versions/`
- Cluster kubeconfig path (ask user if not obvious from context)

## Workflow

### Step 1: Preflight

Verify cluster connectivity: `oc --kubeconfig=<path> get nodes`

### Step 2: Get Group Info

Read `docs/_data/tracking.json` to find the group's compare branch slug. Read `docs/versions/<VERSION>/groups/<GROUP_ID>.md` for the verification command.

### Step 3: Get and Apply MachineConfig Files

From `~/Repositories/go/src/github.com/openshift-kni/telco-reference`, checkout the group's branch and apply:

```bash
oc apply -f <master.yaml>
oc apply -f <worker.yaml>
```

For CRD changes (APIServer, OAuth — groups M10, M11, M12, M30), apply directly. No MCP rollout needed.

### Step 4: Wait for MCP Rollout

Poll MachineConfigPools until Updated=True and Updating=False. **Timeout after 30 minutes** — if not complete, check for Degraded MCPs and report the issue.

For SNO clusters, only the worker MCP exists.

### Step 5: Verify Settings

Run the verification command from the group page against both a master and worker node. Report pass/fail for each setting.

If any setting shows FAIL, investigate (e.g., SSHD first-match-wins ordering, missing file, wrong permissions).

### Step 6: Report Results

| Setting | Expected | Actual | Status |
|---------|----------|--------|--------|
| ... | ... | ... | PASS/FAIL |

## Important Notes

- MachineConfig changes trigger rolling node reboots (~15 min for 5 nodes)
- SSHD drop-ins must use `00-` prefix to load before `50-redhat.conf`
