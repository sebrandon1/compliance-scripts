#!/bin/bash
set -euo pipefail

# Orchestration script to test compliance remediations safely
# This script captures baseline, applies remediations, validates health, and runs functional tests

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
	cat <<EOF
Usage: $0 [OPTIONS] <severity>

Test compliance remediations by capturing baseline, applying changes,
validating cluster health, and running functional tests.

Arguments:
  <severity>           Severity level to test: high | medium | low

Options:
  --skip-baseline      Skip baseline capture (use existing baseline)
  --skip-apply         Skip remediation application (test current state)
  --skip-validation    Skip health validation
  --skip-functional    Skip functional tests
  --baseline-file FILE Use specific baseline file instead of latest
  --dry-run            Show what would be done without executing
  -h, --help           Show this help message

Examples:
  # Full test of high severity remediations
  $0 high

  # Test with existing baseline
  $0 --skip-baseline medium

  # Only validate and test (no baseline or apply)
  $0 --skip-baseline --skip-apply low

  # Dry run to see what would happen
  $0 --dry-run high
EOF
	exit 1
}

# Default options
SKIP_BASELINE=false
SKIP_APPLY=false
SKIP_VALIDATION=false
SKIP_FUNCTIONAL=false
BASELINE_FILE=""
DRY_RUN=false
SEVERITY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
		--skip-baseline)
			SKIP_BASELINE=true
			shift
			;;
		--skip-apply)
			SKIP_APPLY=true
			shift
			;;
		--skip-validation)
			SKIP_VALIDATION=true
			shift
			;;
		--skip-functional)
			SKIP_FUNCTIONAL=true
			shift
			;;
		--baseline-file)
			BASELINE_FILE="$2"
			shift 2
			;;
		--dry-run)
			DRY_RUN=true
			shift
			;;
		-h|--help)
			usage
			;;
		high|medium|low)
			SEVERITY="$1"
			shift
			;;
		*)
			echo "[ERROR] Unknown argument: $1"
			usage
			;;
	esac
done

if [[ -z "$SEVERITY" ]]; then
	echo "[ERROR] Severity level required (high|medium|low)"
	usage
fi

# Check prerequisites
if ! command -v oc >/dev/null 2>&1; then
	echo "[ERROR] 'oc' CLI is required."
	exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
	echo "[ERROR] 'python3' is required."
	exit 1
fi

if ! oc whoami >/dev/null 2>&1; then
	echo "[ERROR] Not logged into a cluster. Please run 'oc login' first."
	exit 1
fi

# Print test plan
echo "=" | tr '=' '=' | head -c 70; echo
echo "Compliance Remediation Test Plan"
echo "=" | tr '=' '=' | head -c 70; echo
echo "Severity: $SEVERITY"
echo "Baseline: $([ "$SKIP_BASELINE" = true ] && echo "Skip" || echo "Capture")"
echo "Apply: $([ "$SKIP_APPLY" = true ] && echo "Skip" || echo "Execute")"
echo "Validation: $([ "$SKIP_VALIDATION" = true ] && echo "Skip" || echo "Execute")"
echo "Functional: $([ "$SKIP_FUNCTIONAL" = true ] && echo "Skip" || echo "Execute")"
echo "Dry Run: $DRY_RUN"
echo "=" | tr '=' '=' | head -c 70; echo

if [ "$DRY_RUN" = true ]; then
	echo "[DRY-RUN] No actual changes will be made"
	exit 0
fi

# Timestamp for this test run
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
TEST_RUN_DIR="$REPO_DIR/test-runs"
mkdir -p "$TEST_RUN_DIR"

# Create a test run directory for this specific run
RUN_DIR="$TEST_RUN_DIR/run-$SEVERITY-$TIMESTAMP"
mkdir -p "$RUN_DIR"

echo "[INFO] Test run directory: $RUN_DIR"

# Log file for this run
LOG_FILE="$RUN_DIR/test-run.log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "[INFO] Test started at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Track overall success
OVERALL_SUCCESS=true

#############################
# Step 1: Capture Baseline
#############################
if [ "$SKIP_BASELINE" = false ]; then
	echo ""
	echo "=" | tr '=' '=' | head -c 70; echo
	echo "Step 1: Capturing Baseline"
	echo "=" | tr '=' '=' | head -c 70; echo
	
	BASELINE_OUTPUT="$RUN_DIR/baseline.json"
	
	if python3 "$SCRIPT_DIR/capture-baseline.py" "$BASELINE_OUTPUT"; then
		echo "[SUCCESS] Baseline captured successfully"
		BASELINE_FILE="$BASELINE_OUTPUT"
	else
		echo "[ERROR] Failed to capture baseline"
		OVERALL_SUCCESS=false
		exit 1
	fi
else
	echo "[INFO] Skipping baseline capture"
	if [[ -z "$BASELINE_FILE" ]]; then
		# Use latest baseline
		if [[ -f "$REPO_DIR/cluster-baseline-latest.json" ]]; then
			BASELINE_FILE="$REPO_DIR/cluster-baseline-latest.json"
			echo "[INFO] Using existing baseline: $BASELINE_FILE"
		else
			echo "[ERROR] No baseline file found. Run without --skip-baseline first."
			exit 1
		fi
	fi
fi

#############################
# Step 2: Apply Remediations
#############################
if [ "$SKIP_APPLY" = false ]; then
	echo ""
	echo "=" | tr '=' '=' | head -c 70; echo
	echo "Step 2: Applying Compliance Remediations"
	echo "=" | tr '=' '=' | head -c 70; echo
	
	# Check if complianceremediations directory exists and has files for this severity
	REMEDIATION_DIR="$REPO_DIR/complianceremediations"
	REMEDIATION_FILES=""
	
	if [ -d "$REMEDIATION_DIR" ]; then
		# Check for remediation files
		REMEDIATION_FILES=$(\
			(
				# Root-level combined files matching *-<severity>-combo.yaml
				find "$REMEDIATION_DIR" -maxdepth 1 -type f -name "*-$SEVERITY-combo.yaml" 2>/dev/null || true
				# Per-severity subdirectory combined files only
				find "$REMEDIATION_DIR/$SEVERITY" -type f -name "*-combo.yaml" 2>/dev/null || true
			) | sort -u
		)
	fi
	
	if [ -z "$REMEDIATION_FILES" ]; then
		echo "[ERROR] No remediations found for severity: $SEVERITY"
		echo ""
		echo "To collect remediations, run the following workflow first:"
		echo "  1. Install compliance operator:  make install-compliance-operator"
		echo "  2. Apply periodic scan:          make apply-periodic-scan"
		echo "  3. Create scan:                  make create-scan"
		echo "  4. Wait for scans to complete:   ./monitor-inprogress-scans.sh --watch"
		echo "  5. Collect remediations:         make collect-complianceremediations"
		echo "  6. Combine MachineConfigs:       make combine-machineconfigs"
		echo ""
		echo "Or run the full workflow:         make full-workflow"
		echo ""
		echo "Expected remediation locations:"
		echo "  - $REMEDIATION_DIR/*-$SEVERITY-combo.yaml"
		echo "  - $REMEDIATION_DIR/$SEVERITY/*-combo.yaml"
		exit 1
	fi
	
	REMEDIATION_COUNT=$(echo "$REMEDIATION_FILES" | grep -c ".")
	echo "[INFO] Found $REMEDIATION_COUNT remediation file(s) for severity: $SEVERITY"
	
	# Run the apply script
	if bash "$REPO_DIR/apply-remediations-by-severity.sh" "$SEVERITY"; then
		echo "[SUCCESS] Remediations applied successfully"
		
		# Wait a bit for cluster to stabilize after MachineConfig changes
		echo "[INFO] Waiting 60 seconds for cluster to stabilize..."
		sleep 60
	else
		echo "[ERROR] Failed to apply remediations"
		OVERALL_SUCCESS=false
		
		# Still continue to validation to see what broke
		echo "[WARNING] Continuing to validation despite apply failure..."
	fi
else
	echo "[INFO] Skipping remediation application"
fi

#############################
# Step 3: Validate Health
#############################
if [ "$SKIP_VALIDATION" = false ]; then
	echo ""
	echo "=" | tr '=' '=' | head -c 70; echo
	echo "Step 3: Validating Cluster Health"
	echo "=" | tr '=' '=' | head -c 70; echo
	
	if python3 "$SCRIPT_DIR/validate-cluster-health.py" "$BASELINE_FILE"; then
		echo "[SUCCESS] Cluster health validation passed"
		cp "$REPO_DIR"/cluster-validation-*.json "$RUN_DIR/" 2>/dev/null || true
	else
		echo "[ERROR] Cluster health validation failed"
		OVERALL_SUCCESS=false
		cp "$REPO_DIR"/cluster-validation-*.json "$RUN_DIR/" 2>/dev/null || true
		
		# Continue to functional tests to get more data
		echo "[WARNING] Continuing to functional tests despite validation failure..."
	fi
else
	echo "[INFO] Skipping health validation"
fi

#############################
# Step 4: Functional Tests
#############################
if [ "$SKIP_FUNCTIONAL" = false ]; then
	echo ""
	echo "=" | tr '=' '=' | head -c 70; echo
	echo "Step 4: Running Functional Tests"
	echo "=" | tr '=' '=' | head -c 70; echo
	
	if python3 "$SCRIPT_DIR/test-ocp-functionality.py"; then
		echo "[SUCCESS] Functional tests passed"
		cp "$REPO_DIR"/functional-test-results-*.json "$RUN_DIR/" 2>/dev/null || true
	else
		echo "[ERROR] Functional tests failed"
		OVERALL_SUCCESS=false
		cp "$REPO_DIR"/functional-test-results-*.json "$RUN_DIR/" 2>/dev/null || true
	fi
else
	echo "[INFO] Skipping functional tests"
fi

#############################
# Final Summary
#############################
echo ""
echo "=" | tr '=' '=' | head -c 70; echo
echo "Test Run Summary"
echo "=" | tr '=' '=' | head -c 70; echo
echo "Test completed at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Severity tested: $SEVERITY"
echo "Results directory: $RUN_DIR"
echo ""

if [ "$OVERALL_SUCCESS" = true ]; then
	echo "✅ ALL TESTS PASSED"
	echo ""
	echo "The compliance remediations for severity '$SEVERITY' appear to be safe."
	echo "No critical issues detected in cluster health or functionality."
	exit 0
else
	echo "❌ TEST FAILURES DETECTED"
	echo ""
	echo "The compliance remediations for severity '$SEVERITY' may have caused issues."
	echo "Review the test results in: $RUN_DIR"
	echo ""
	echo "Recommended actions:"
	echo "  1. Review validation results: $RUN_DIR/cluster-validation-*.json"
	echo "  2. Review functional test results: $RUN_DIR/functional-test-results-*.json"
	echo "  3. Check cluster operators: oc get co"
	echo "  4. Check machine config pools: oc get mcp"
	echo "  5. Consider rolling back the changes if critical systems are affected"
	exit 1
fi

