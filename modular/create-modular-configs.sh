#!/bin/bash

# Wrapper script to create modular MachineConfig files
# This script integrates the split-machineconfigs-modular.py script into the workflow

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Default directories
source_dir="complianceremediations"
modular_dir="complianceremediations/modular"
severity="high"

usage() {
	echo "Usage: $0 [-s severity] [-i input-dir] [-o output-dir] [-h]"
	echo "  -s  Severity level(s) to process: high,medium,low (default: high)"
	echo "  -i  Input directory for remediation YAMLs (default: $source_dir)"
	echo "  -o  Output directory for modular YAMLs (default: $modular_dir)"
	echo "  -h  Show this help message"
	echo ""
	echo "This script creates modular MachineConfig files using .d directory includes."
	echo "It generates:"
	echo "  1. Base files that enable include directories (e.g., /etc/ssh/sshd_config.d/)"
	echo "  2. Individual modular files for each remediation"
	echo ""
	echo "Example: $0 -s high,medium"
	exit 1
}

while getopts "s:i:o:h" opt; do
	case $opt in
	s) severity="$OPTARG" ;;
	i) source_dir="$OPTARG" ;;
	o) modular_dir="$OPTARG" ;;
	h) usage ;;
	*) usage ;;
	esac
done

# Ensure Python virtual environment is activated
if [[ ! -d "venv" ]]; then
	log_error "Python virtual environment not found."
	log_error "Please run: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
	exit 1
fi

# Activate venv if not already active
if [[ -z "$VIRTUAL_ENV" ]]; then
	log_info "Activating Python virtual environment..."
	# shellcheck disable=SC1091
	source venv/bin/activate
fi

MODULAR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$MODULAR_DIR/split-machineconfigs-modular.py" ]]; then
	log_error "split-machineconfigs-modular.py not found in $MODULAR_DIR"
	exit 1
fi

log_info "Creating modular MachineConfig files..."
log_info "  Source: $source_dir"
log_info "  Output: $modular_dir"
log_info "  Severity: $severity"
echo ""

python3 "$MODULAR_DIR/split-machineconfigs-modular.py" \
	--src-dir "$source_dir" \
	--out-dir "$modular_dir" \
	-s "$severity"

# Check if any files were created
if [[ ! -d "$modular_dir" ]] || [[ -z "$(ls -A "$modular_dir" 2>/dev/null)" ]]; then
	log_warn "No modular files were created."
	log_warn "This could mean:"
	log_warn "  1. No remediation files found in $source_dir"
	log_warn "  2. No files match the severity filter: $severity"
	log_warn "  3. No files target modular paths (sshd_config, pam.d files)"
	exit 0
fi

echo ""
log_success "Modular files created successfully!"
echo ""
echo "Next steps:"
echo "  1. Review the generated files in: $modular_dir"
echo "  2. Use core/organize-machine-configs.sh to copy them to the target repository"
echo "  3. Or apply them directly with: oc apply -f $modular_dir/"
echo ""
echo "Example:"
echo "  ./core/organize-machine-configs.sh -d $modular_dir -s $severity"
echo ""
