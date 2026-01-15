#!/bin/bash
# lib/common.sh - Shared functions for compliance-scripts
#
# Source this file at the top of scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh"

# Strict mode
set -euo pipefail

# ============================================================================
# COLORS (only if terminal supports it)
# ============================================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    BOLD=''
    NC=''
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*"
    fi
}

# ============================================================================
# DEPENDENCY CHECKS
# ============================================================================

# Check if a command exists
# Usage: require_cmd oc yq jq
require_cmd() {
    local missing=0
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "'$cmd' is required but not installed"
            missing=1
        fi
    done
    [[ $missing -eq 1 ]] && exit 1
    return 0
}

# Check cluster connectivity
require_cluster() {
    if ! oc whoami &>/dev/null 2>&1; then
        log_error "Not connected to OpenShift cluster. Run 'oc login' first."
        exit 1
    fi
}

# ============================================================================
# ENVIRONMENT & CONFIGURATION
# ============================================================================

# Load .env file if it exists
# Usage: load_env [path/to/.env]
load_env() {
    local env_file="${1:-.env}"
    if [[ -f "$env_file" ]]; then
        log_debug "Loading config from $env_file"
        # shellcheck source=/dev/null
        source "$env_file"
    fi
}

# Get script directory (call from the script itself)
# Usage: SCRIPT_DIR=$(get_script_dir)
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
}

# Get repository root directory
get_repo_root() {
    cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd
}

# ============================================================================
# TIMING & CLEANUP
# ============================================================================

# Track start time for duration calculation
# Usage: start_timer
start_timer() {
    export _START_TIME
    _START_TIME=$(date +%s)
}

# Print duration since start_timer was called
# Usage: print_duration
print_duration() {
    if [[ -n "${_START_TIME:-}" ]]; then
        local duration=$(($(date +%s) - _START_TIME))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        if [[ $minutes -gt 0 ]]; then
            log_info "Duration: ${minutes}m ${seconds}s"
        else
            log_info "Duration: ${seconds}s"
        fi
    fi
}

# Setup cleanup trap with duration printing
# Usage: setup_cleanup
setup_cleanup() {
    start_timer
    trap 'print_duration' EXIT
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Wait for a condition with timeout
# Usage: wait_for "condition description" timeout_seconds command args...
wait_for() {
    local description="$1"
    local timeout="$2"
    shift 2
    local elapsed=0
    local interval=5

    log_info "Waiting for $description (timeout: ${timeout}s)..."
    while ! "$@" &>/dev/null; do
        sleep $interval
        elapsed=$((elapsed + interval))
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for $description"
            return 1
        fi
        echo -n "."
    done
    echo ""
    log_success "$description ready"
    return 0
}

# Confirm action with user
# Usage: confirm "Are you sure?" && do_something
confirm() {
    local prompt="${1:-Continue?}"
    read -r -p "$prompt [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================================
# DRY RUN SUPPORT
# ============================================================================

# Global dry-run flag (scripts should set this based on CLI args)
DRY_RUN="${DRY_RUN:-false}"

# Apply a Kubernetes resource (respects DRY_RUN)
# Usage: apply_resource file.yaml
apply_resource() {
    local file="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would apply: $file"
        oc apply --dry-run=server -f "$file"
    else
        oc apply -f "$file"
    fi
}

# Apply inline YAML (respects DRY_RUN)
# Usage: echo "yaml..." | apply_inline
apply_inline() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would apply inline resource"
        oc apply --dry-run=server -f -
    else
        oc apply -f -
    fi
}
