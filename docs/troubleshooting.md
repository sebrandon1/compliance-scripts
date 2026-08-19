# Troubleshooting

## "Some pods in 'openshift-marketplace' are not Ready"

This can occur due to race conditions with the marketplace operator's catalog reconciliation. The marketplace operator continuously refreshes catalog source pods, and a new pod might appear right after the readiness check passes. The script ignores pods created less than 30 seconds ago to avoid this.

If you see this error, check whether the failing pods are very young (a few seconds old) — that indicates the race condition, not an actual problem.

## CRC Cluster Startup Issues

The `test-compliance-versions` workflow provisions clusters with `palmsoftware/quick-ocp` (OCP 4.20/4.21, operator v1.8.2/v1.9.0). It still uses the `CRC_PULL_SECRET` secret as the pull secret:
- Ensure the `CRC_PULL_SECRET` secret is configured
- API server "connection refused" errors during startup are normal

## ProfileBundle Not Reaching VALID Status

The install script waits up to 5 minutes for ProfileBundles to become `VALID`. If they remain in `PENDING`:
1. Check if profile parser pods have ImagePullBackOff errors
2. Verify the operator version supports your cluster architecture (ARM64 only supported in v1.7.0+)
3. Check for storage issues — the operator needs a working StorageClass

## Downloading Full CI Logs

GitHub Actions truncates log output in the UI. To get complete logs:

```bash
gh run view <run-id> --repo sebrandon1/compliance-scripts
gh api repos/sebrandon1/compliance-scripts/actions/runs/<run-id>/logs > logs.zip
unzip logs.zip -d gha-logs
grep -i "error\|fail" gha-logs/*.txt
```

## Operator Versioning

There are two distribution channels with different version numbers:

- **Upstream/community** at [ComplianceAsCode/compliance-operator](https://github.com/ComplianceAsCode/compliance-operator), used by the install script's `--co-ref` flag. Current pins in `versions.env` are operator **v1.9.0** and content **v0.1.81**. CI tests v1.8.2 and v1.9.0. ARM64 needs v1.7.0 or later.
- **Red Hat certified**, installed automatically when `redhat-operators` is present in `openshift-marketplace`. Uses its own versioning and is not publicly tagged on GitHub.

The old downstream repo at [openshift/compliance-operator](https://github.com/openshift/compliance-operator) is deprecated.

Upstream images from `ghcr.io/complianceascode` are mirrored to `quay.io/bapalm` for reliability. The install script automatically falls back to the mirror if the upstream tag is unavailable. To manually mirror: `make mirror-images CO_REF=v1.9.0`.
