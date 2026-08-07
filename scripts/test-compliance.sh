#!/bin/bash
# test-compliance.sh - Run compliance validation on a local OpenShift cluster
#
# This script validates that the Compliance Operator is properly installed and
# configured by running through the full install/scan workflow and asserting
# that all expected resources exist.
#
# Usage:
#   ./scripts/test-compliance.sh
#
# Requires: oc (connected to a cluster)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

NS="${NAMESPACE:-openshift-compliance}"

step() {
	local num="$1"
	local total="$2"
	local desc="$3"
	echo ""
	echo "Step ${num}/${total}: ${desc}"
}

assert_resource() {
	local kind="$1"
	local name="$2"
	retry 3 10 oc -n "$NS" get "$kind" "$name"
}

# Step 1: Install Compliance Operator
step 1 9 "Installing Compliance Operator..."
"$SCRIPT_DIR/core/install-compliance-operator.sh"
log_success "Compliance Operator installation completed"

# Step 2: Wait for pods to be Ready
step 2 9 "Waiting for Compliance Operator pods to be Ready..."
retry 3 5 oc -n "$NS" get pods
wait_for 3 10 "Waiting for pods to appear" oc -n "$NS" get pods -o jsonpath='{.items[0].metadata.name}'

NSPODS=$(oc -n "$NS" get pods -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{"\n"}{end}' | tr '\n' ' ' | xargs || true)
if [[ -n "$NSPODS" ]]; then
	# shellcheck disable=SC2086
	oc -n "$NS" wait --for=condition=Ready pod $NSPODS --timeout=600s
fi
log_success "All Compliance Operator pods are Ready"

# Step 3: Assert ProfileBundles exist
step 3 9 "Asserting ProfileBundles exist..."
assert_resource profilebundle ocp4
assert_resource profilebundle rhcos4
log_success "ProfileBundles ocp4 and rhcos4 exist"

# Step 4: Apply periodic scan configuration
step 4 9 "Applying periodic scan configuration..."
"$SCRIPT_DIR/core/apply-periodic-scan.sh"
log_success "Periodic scan configuration applied"

# Step 5: Assert periodic scan resources exist
step 5 9 "Asserting periodic scan resources exist..."
oc -n "$NS" get scansetting periodic-setting
if profile_exists ocp4-e8 "$NS"; then
	oc -n "$NS" get scansettingbinding periodic-e8
	log_success "periodic-e8 binding exists"
else
	log_warn "E8 profiles not available, periodic-e8 binding skipped"
fi
log_success "Periodic scan resources exist"

# Step 6: Assert scan Profiles exist
step 6 9 "Asserting scan Profiles exist..."
if profile_exists ocp4-e8 "$NS"; then
	log_success "ocp4-e8"
else
	log_warn "ocp4-e8 not available (may be removed in this operator version)"
fi
if profile_exists rhcos4-e8 "$NS"; then
	log_success "rhcos4-e8"
else
	log_warn "rhcos4-e8 not available (may be removed in this operator version)"
fi
assert_resource profile ocp4-cis
assert_resource profile ocp4-moderate
log_success "Required profiles exist"

# Step 7: Assert ComplianceSuites for periodic scans exist
step 7 9 "Asserting ComplianceSuites for periodic scans exist..."
log_info "Waiting for operator to reconcile ScanSettingBindings into ComplianceSuites..."
wait_for 30 10 "Waiting for ComplianceSuites to be created" \
	oc -n "$NS" get compliancesuite cis-scan
log_success "ComplianceSuite cis-scan exists"

if profile_exists ocp4-e8 "$NS"; then
	oc -n "$NS" get compliancesuite periodic-e8
	log_success "ComplianceSuite periodic-e8 exists"
else
	log_warn "ComplianceSuite periodic-e8 skipped (E8 profiles not available)"
fi
log_success "ComplianceSuites exist"

# Step 8: Create compliance scans (all profiles)
step 8 9 "Creating compliance scans (all profiles)..."
"$SCRIPT_DIR/core/create-scan.sh"
log_success "Compliance scans created"

# Step 9: Assert on-demand scan resources exist
step 9 9 "Asserting on-demand scan resources exist..."
oc -n "$NS" get scansetting default

for profile in ocp4-cis ocp4-moderate ocp4-pci-dss rhcos4-moderate; do
	oc -n "$NS" get scansettingbinding "${profile}-scan"
done

for profile in ocp4-e8 rhcos4-e8; do
	if profile_exists "$profile" "$NS"; then
		oc -n "$NS" get scansettingbinding "${profile}-scan"
	else
		log_warn "${profile}-scan skipped (profile not available)"
	fi
done
log_success "All scan resources exist"

echo ""
log_success "COMPLIANCE VALIDATION COMPLETED SUCCESSFULLY"
log_info "All assertions passed"
