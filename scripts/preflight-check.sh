#!/bin/bash
# scripts/preflight-check.sh - Validate dependencies for compliance-scripts
#
# Usage: ./scripts/preflight-check.sh [--quiet]
#
# Checks for required CLI tools, Python packages, and cluster connectivity.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

# ============================================================================
# MAIN
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       Compliance Scripts - Preflight Check                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

FAILED=0
WARNINGS=0

# ----------------------------------------------------------------------------
# Required CLI Tools
# ----------------------------------------------------------------------------
echo "${BOLD}Checking CLI tools...${NC}"

REQUIRED_TOOLS=(oc yq jq python3)
for cmd in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        version=$("$cmd" --version 2>/dev/null | head -1 || echo "version unknown")
        log_success "$cmd: $version"
    else
        log_error "$cmd: NOT FOUND"
        FAILED=1
    fi
done

# Optional tools
OPTIONAL_TOOLS=(shellcheck shfmt)
for cmd in "${OPTIONAL_TOOLS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        log_success "$cmd: found (optional - for linting)"
    else
        log_warn "$cmd: not found (optional - for linting)"
        WARNINGS=$((WARNINGS + 1))
    fi
done

echo ""

# ----------------------------------------------------------------------------
# Python Environment
# ----------------------------------------------------------------------------
echo "${BOLD}Checking Python environment...${NC}"

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [[ "$PYTHON_MAJOR" -ge 3 ]] && [[ "$PYTHON_MINOR" -ge 6 ]]; then
    log_success "Python $PYTHON_VERSION (3.6+ required)"
else
    log_error "Python $PYTHON_VERSION is too old (3.6+ required)"
    FAILED=1
fi

# Check PyYAML
if python3 -c "import yaml; print(f'pyyaml {yaml.__version__}')" 2>/dev/null; then
    log_success "$(python3 -c "import yaml; print(f'pyyaml {yaml.__version__}')")"
else
    log_error "pyyaml: NOT INSTALLED"
    log_info "  Install with: pip install pyyaml"
    FAILED=1
fi

echo ""

# ----------------------------------------------------------------------------
# Cluster Connectivity (Optional)
# ----------------------------------------------------------------------------
echo "${BOLD}Checking cluster connectivity...${NC}"

if oc whoami &>/dev/null 2>&1; then
    CLUSTER_USER=$(oc whoami 2>/dev/null)
    CLUSTER_SERVER=$(oc whoami --show-server 2>/dev/null || echo "unknown")
    log_success "Connected as: $CLUSTER_USER"
    log_success "Cluster: $CLUSTER_SERVER"

    # Check for Compliance Operator
    if oc get crd compliancescans.compliance.openshift.io &>/dev/null 2>&1; then
        log_success "Compliance Operator: installed"
    else
        log_warn "Compliance Operator: not detected (run install-compliance-operator.sh)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    log_warn "Not connected to cluster"
    log_info "  Some scripts require cluster access. Run 'oc login' first."
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# ----------------------------------------------------------------------------
# Directory Structure
# ----------------------------------------------------------------------------
echo "${BOLD}Checking repository structure...${NC}"

EXPECTED_DIRS=(core utilities modular lib)
for dir in "${EXPECTED_DIRS[@]}"; do
    if [[ -d "$SCRIPT_DIR/$dir" ]]; then
        log_success "$dir/ directory exists"
    else
        log_error "$dir/ directory missing"
        FAILED=1
    fi
done

echo ""

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
echo "════════════════════════════════════════════════════════════════"
if [[ $FAILED -eq 0 ]]; then
    if [[ $WARNINGS -gt 0 ]]; then
        log_success "All required checks passed! ($WARNINGS warnings)"
    else
        log_success "All checks passed!"
    fi
    echo ""
    echo "You're ready to run compliance scripts."
    echo "Start with: make help"
    exit 0
else
    log_error "Some checks failed. Please resolve the issues above."
    exit 1
fi
