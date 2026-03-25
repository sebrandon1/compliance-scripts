# Verify Remediation Group on Cluster

Apply a group's MachineConfig to a live OCP cluster, wait for rollout, and verify the settings are active.

## Inputs

The user provides:
- Group ID (e.g., M1, M4, M26)
- Cluster kubeconfig path (default: `~/Downloads/cnfdt16-kubeconfig`)

## Workflow

### Step 1: Get Group Info

Read `docs/_data/tracking.json` to find the group's compare branch slug. Read the group page in `docs/versions/4.22/groups/<GROUP_ID>.md` for the verification command.

### Step 2: Get MachineConfig Files

From `~/Repositories/go/src/github.com/openshift-kni/telco-reference`, checkout the group's branch and extract the YAML files.

### Step 3: Apply MachineConfigs

```bash
oc apply -f <master.yaml>
oc apply -f <worker.yaml>
```

For CRD changes (APIServer, OAuth), apply directly — no MCP rollout needed.

### Step 4: Wait for MCP Rollout

Poll MachineConfigPools until both master and worker show Updated=True, Updating=False:

```bash
while true; do
  M_UPDATED=$(oc get mcp master -o jsonpath='{.status.conditions[?(@.type=="Updated")].status}')
  W_UPDATED=$(oc get mcp worker -o jsonpath='{.status.conditions[?(@.type=="Updated")].status}')
  # ... check both True
  sleep 15
done
```

Typical rollout: ~15 minutes for 5 nodes.

### Step 5: Verify Settings

Run the verification command from the group page against a master and worker node. Report pass/fail for each setting.

### Step 6: Report Results

Present a table:

| Setting | Expected | Actual | Status |
|---------|----------|--------|--------|
| ... | ... | ... | PASS/FAIL |

## Important Notes

- MachineConfig changes trigger rolling node reboots — one node at a time
- SSHD drop-ins must use `00-` prefix to load before `50-redhat.conf`
- Always verify on both master and worker nodes
- For SNO clusters, only worker MCP exists
- CRD changes (M10, M11, M12, M30) don't require node reboots
