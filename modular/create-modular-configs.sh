#!/bin/bash

# Wrapper script to create modular MachineConfig files
# This script integrates the split-machineconfigs-modular.py script into the workflow

set -e

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
	echo "Error: Python virtual environment not found."
	echo "Please run: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
	exit 1
fi

# Activate venv if not already active
if [[ -z "$VIRTUAL_ENV" ]]; then
	echo "Activating Python virtual environment..."
	# shellcheck disable=SC1091
	source venv/bin/activate
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if split-machineconfigs-modular.py exists
if [[ ! -f "$SCRIPT_DIR/split-machineconfigs-modular.py" ]]; then
	echo "Error: split-machineconfigs-modular.py not found in $SCRIPT_DIR"
	exit 1
fi

# Run the modular split script
echo "Creating modular MachineConfig files..."
echo "  Source: $source_dir"
echo "  Output: $modular_dir"
echo "  Severity: $severity"
echo ""

python3 "$SCRIPT_DIR/split-machineconfigs-modular.py" \
	--src-dir "$source_dir" \
	--out-dir "$modular_dir" \
	-s "$severity"

# Check if any files were created
if [[ ! -d "$modular_dir" ]] || [[ -z "$(ls -A "$modular_dir" 2>/dev/null)" ]]; then
	echo "Warning: No modular files were created."
	echo "This could mean:"
	echo "  1. No remediation files found in $source_dir"
	echo "  2. No files match the severity filter: $severity"
	echo "  3. No files target modular paths (sshd_config, pam.d files)"
	exit 0
fi

# Display summary
echo ""
echo "========================================"
echo "Modular files created successfully!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Review the generated files in: $modular_dir"
echo "  2. Use core/organize-machine-configs.sh to copy them to the target repository"
echo "  3. Or apply them directly with: oc apply -f $modular_dir/"
echo ""
echo "Example:"
echo "  ./core/organize-machine-configs.sh -d $modular_dir -s $severity"
echo ""
