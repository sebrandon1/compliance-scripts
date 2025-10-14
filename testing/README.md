# 🧪 Compliance Remediation Testing Framework

This testing framework validates that OpenShift compliance remediations don't break cluster functionality. It provides automated baseline capture, health validation, and functional testing to ensure your compliance changes are safe.

## 📋 Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Testing Scripts](#testing-scripts)
- [Workflow](#workflow)
- [Usage Examples](#usage-examples)
- [Understanding Test Results](#understanding-test-results)
- [Best Practices](#best-practices)

## Overview

The testing framework consists of four main components:

1. **Baseline Capture** - Snapshots cluster health before changes
2. **Health Validation** - Compares cluster state against baseline
3. **Functional Tests** - Verifies OCP capabilities still work
4. **Orchestration** - Automates the entire test workflow

## Quick Start

### Prerequisites

- `oc` CLI logged into your OpenShift cluster
- `python3` installed
- Sufficient cluster permissions to create/delete projects and resources

### Basic Usage

Test your high severity remediations:

```bash
# From the testing directory
cd testing
make test-high
```

Or run the test script directly:

```bash
# From the testing directory
./run-compliance-tests.sh high
```

Or from the repo root:

```bash
# From the repo root
./testing/run-compliance-tests.sh high
```

## Testing Scripts

### 1. capture-baseline.py

Captures the current state of your OpenShift cluster as a baseline for comparison.

**What it captures:**
- Cluster operator status (available, progressing, degraded)
- Node health and conditions
- MachineConfigPool status
- Cluster version information
- API server accessibility
- etcd health
- Critical namespace pod counts

**Usage:**
```bash
python3 capture-baseline.py [output-file.json]

# Or via Makefile (from testing directory)
make baseline
```

**Output:**
- Creates `cluster-baseline-TIMESTAMP.json`
- Creates symlink `cluster-baseline-latest.json` pointing to the latest baseline

**Example output:**
```
======================================================================
OpenShift Cluster Baseline Capture
======================================================================
[INFO] Capturing cluster operators status...
[INFO] Capturing nodes status...
[INFO] Capturing MachineConfigPool status...
[SUCCESS] Baseline saved to cluster-baseline-20241009T143052Z.json

======================================================================
Baseline Summary
======================================================================

Cluster Operators: 28
Nodes: 3
MachineConfigPools: 2
  - master: 3/3 updated
  - worker: 2/2 updated
Cluster Version: 4.15.0
```

### 2. validate-cluster-health.py

Validates cluster health by comparing current state against a baseline.

**What it validates:**
- Cluster operators didn't become degraded or unavailable
- Nodes remain ready and healthy
- MachineConfigPools are not degraded
- API server is still accessible

**Usage:**
```bash
python3 validate-cluster-health.py [baseline-file.json]

# Defaults to cluster-baseline-latest.json if not specified

# Or via Makefile (from testing directory)
make validate
```

**Output:**
- Detailed validation results with issues and warnings
- JSON report: `cluster-validation-TIMESTAMP.json`
- Exit code 0 on success, 1 on failure

**Example output:**
```
======================================================================
Cluster Operators Validation
======================================================================
✅ All cluster operators healthy

======================================================================
Nodes Validation
======================================================================
✅ All nodes healthy

======================================================================
MachineConfigPools Validation
======================================================================
⚠️  WARNINGS:
  ⚠️  worker: 1/2 machines updated
  ⚠️  worker: still updating

======================================================================
Validation Summary
======================================================================
✅ VALIDATION PASSED - Cluster appears healthy
   No critical issues detected after remediation
```

### 3. test-ocp-functionality.py

Runs functional tests to verify that key OCP capabilities are working.

**What it tests:**
- Project/namespace creation
- Pod deployment and lifecycle
- Service creation and networking
- Deployment with multiple replicas
- ConfigMap and Secret creation
- Route creation and exposure
- PersistentVolumeClaim provisioning
- Build capability (BuildConfig/ImageStream)

**Usage:**
```bash
python3 test-ocp-functionality.py

# Or via Makefile (from testing directory)
make functional
```

**Output:**
- Real-time test progress with pass/fail indicators
- JSON report: `functional-test-results-TIMESTAMP.json`
- Exit code 0 if all tests pass, 1 if any fail

**Example output:**
```
======================================================================
Test: Project Creation
======================================================================
[TEST] Creating project test-compliance-a3f9k2...
✅ Project created successfully

======================================================================
Test: Pod Deployment
======================================================================
[TEST] Deploying test pod in test-compliance-a3f9k2...
[TEST] Waiting for pod to be Running...
✅ Pod is running

======================================================================
Test Results Summary
======================================================================
Tests Passed: 8/8

Detailed Results:
  ✅ PASS - Project Creation
  ✅ PASS - Pod Deployment
  ✅ PASS - Service Creation
  ✅ PASS - Deployment Replicas
  ✅ PASS - Configmap Secret
  ✅ PASS - Route Creation
  ✅ PASS - Pvc Creation
  ✅ PASS - Build Capability

✅ ALL TESTS PASSED
```

### 4. run-compliance-tests.sh

Orchestrates the complete testing workflow: baseline → apply → validate → test.

**Usage:**
```bash
./run-compliance-tests.sh [OPTIONS] <severity>

Options:
  --skip-baseline      Skip baseline capture (use existing baseline)
  --skip-apply         Skip remediation application (test current state)
  --skip-validation    Skip health validation
  --skip-functional    Skip functional tests
  --baseline-file FILE Use specific baseline file instead of latest
  --dry-run            Show what would be done without executing
  -h, --help           Show help message
```

**Examples:**
```bash
# Full test of high severity remediations
./run-compliance-tests.sh high

# Test with existing baseline
./run-compliance-tests.sh --skip-baseline medium

# Only validate and test (no baseline or apply)
./run-compliance-tests.sh --skip-baseline --skip-apply low

# Dry run to see what would happen
./run-compliance-tests.sh --dry-run high
```

**Output:**
- Creates `test-runs/run-SEVERITY-TIMESTAMP/` directory
- Saves all reports and logs in the test run directory
- Exit code 0 on success, 1 on failure

## Workflow

### Recommended Testing Workflow

```
1. Capture Baseline
   ↓
2. Apply Remediations (one severity at a time)
   ↓
3. Wait for Cluster Stabilization (MCPs update, nodes reboot)
   ↓
4. Validate Health (compare to baseline)
   ↓
5. Run Functional Tests (verify OCP capabilities)
   ↓
6. Review Results & Decide
   ├─→ Success: Continue to next severity
   └─→ Failure: Review issues and rollback if needed
```

### Testing Severity Levels Incrementally

It's recommended to test remediations in order from high to low:

```bash
# From the testing directory
cd testing

# Step 1: Test high severity first
make test-high

# Review results, if successful proceed

# Step 2: Test medium severity
make test-medium

# Review results, if successful proceed

# Step 3: Test low severity
make test-low
```

## Usage Examples

### Example 1: First Time Testing

```bash
# Navigate to testing directory
cd /path/to/compliance-scripts/testing

# Test high severity remediations (full workflow)
make test-high

# Check the results
ls -la ../test-runs/run-high-*/
```

### Example 2: Re-validate After Manual Changes

```bash
# From testing directory
cd testing

# Capture new baseline
make baseline

# Manually apply some remediations
../apply-remediations-by-severity.sh medium

# Validate health
make validate

# Run functional tests
make functional
```

### Example 3: Testing Multiple Severities in Sequence

```bash
# From testing directory
cd testing

# Use Makefile targets
for target in test-high test-medium test-low; do
    echo "Running $target..."
    make "$target"
    
    if [ $? -ne 0 ]; then
        echo "❌ Testing failed at: $target"
        break
    fi
    
    echo "✅ $target passed, continuing..."
    sleep 30  # Brief pause between tests
done
```

### Example 4: Testing Without Applying Changes

```bash
# From testing directory
# Just capture baseline and validate current state
./run-compliance-tests.sh --skip-apply high
```

## Understanding Test Results

### Test Run Directory Structure

Each test run creates a directory with all results:

```
test-runs/
└── run-high-20241009T143052Z/
    ├── test-run.log                    # Complete execution log
    ├── baseline.json                   # Captured baseline
    ├── cluster-validation-*.json       # Health validation results
    └── functional-test-results-*.json  # Functional test results
```

### Health Validation Results

The validation script categorizes issues into two levels:

**🔴 CRITICAL ISSUES** - Must be addressed:
- Cluster operators became degraded or unavailable
- Nodes became not ready
- MachineConfigPools became degraded
- API server became inaccessible

**🟡 WARNINGS** - Should be reviewed:
- Operators still progressing (may be temporary)
- MachineConfigPools still updating (expected during rollout)
- New pressure conditions on nodes

### Exit Codes

All scripts follow these exit code conventions:
- `0` - Success, all tests passed
- `1` - Failure, critical issues detected

## Best Practices

### 1. Always Capture a Fresh Baseline

Capture a baseline when your cluster is in a known good state:

```bash
# Wait for cluster to be stable
oc wait co --all --for=condition=Available=True --timeout=10m
oc wait mcp --all --for=condition=Updated=True --timeout=30m

# Then capture baseline (from testing directory)
cd testing
make baseline
```

### 2. Test One Severity at a Time

Don't apply all remediations at once. Test incrementally:

```bash
# From testing directory
cd testing

# Good: Test high first
make test-high

# If successful, then medium
make test-medium

# Bad: Don't apply all at once (from repo root)
../apply-remediations-by-severity.sh high
../apply-remediations-by-severity.sh medium  # Too fast!
../apply-remediations-by-severity.sh low
```

### 3. Review Combined MachineConfigs

Before testing, review what will be applied:

```bash
# Check what high severity remediations exist
ls -la complianceremediations/*-high-combo.yaml
ls -la complianceremediations/high/*-combo.yaml

# Review the contents
cat complianceremediations/high/sshd-high-combo.yaml
```

### 4. Wait for MachineConfigPool Updates

MachineConfig changes trigger node reboots. Wait for completion:

```bash
# Monitor MCP status
watch oc get mcp

# Or wait explicitly
oc wait mcp/worker --for=condition=Updated=True --timeout=45m
oc wait mcp/master --for=condition=Updated=True --timeout=45m
```

### 5. Keep Test Results for Comparison

Archive test results for historical comparison:

```bash
# Archive current test runs
tar -czf test-results-$(date +%Y%m%d).tar.gz test-runs/

# Clean up old runs
make clean-test-results
```

### 6. Use Skip Flags for Iteration

When debugging issues, skip steps you've already completed:

```bash
# From testing directory
# Already have a baseline and applied changes
./run-compliance-tests.sh --skip-baseline --skip-apply high
```

### 7. Monitor During Testing

Keep monitoring tools open during testing:

```bash
# Terminal 1: Run tests (from testing directory)
cd testing
make test-high

# Terminal 2: Monitor operators
watch oc get co

# Terminal 3: Monitor nodes
watch oc get nodes

# Terminal 4: Monitor MCPs
watch oc get mcp
```

## Cleaning Up

Remove all test results and baselines:

```bash
# From testing directory
cd testing
make clean
```

This removes:
- `test-runs/` directory (in repo root)
- All baseline JSON files (in repo root)
- All validation JSON files (in repo root)
- All functional test result files (in repo root)
- Applied YAML reports (in repo root)

## Troubleshooting

### Issue: Baseline capture fails

**Solution:** Verify you're logged in and have cluster access:
```bash
oc whoami
oc get nodes

# Ensure you're in the testing directory when using Makefile
cd testing
make baseline
```

### Issue: Validation shows false positives

**Solution:** Ensure baseline was captured in a stable state. Recapture baseline:
```bash
# Wait for stability
oc wait co --all --for=condition=Available=True --timeout=10m

# From testing directory
cd testing
make baseline
```

### Issue: Functional tests fail

**Solution:** Check if cluster has necessary permissions and resources:
```bash
# Check your permissions
oc auth can-i create project
oc auth can-i create pod

# Check if storage is available
oc get storageclass
```

### Issue: Tests timeout

**Solution:** Increase timeout values in the test scripts or check cluster performance:
```bash
# Check node resources
oc adm top nodes

# Check pod resources
oc adm top pods -A
```

## Integration with CI/CD

The testing framework can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Test Compliance Remediations
  run: |
    ./testing/run-compliance-tests.sh high
    
- name: Upload Test Results
  if: always()
  uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: test-runs/
```

## Contributing

When adding new tests:
1. Follow the existing script structure
2. Include proper error handling
3. Provide detailed output messages
4. Update this README with new features
5. Test on a real cluster before committing

## Support

For issues or questions:
1. Check the test run logs in `test-runs/`
2. Review cluster status: `oc get co`, `oc get nodes`, `oc get mcp`
3. Open an issue in the repository with test results attached

