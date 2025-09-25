#!/usr/bin/env bash

set -euo pipefail

# Fetch kubeconfig from a remote host via scp.
# Defaults:
# - Remote: root@10.6.105.126:/root/ocp/auth/kubeconfig
# - Destination: ~/Downloads/cnfdc3-kubeconfig
#
# Usage:
#   ./fetch-kubeconfig.sh                   # use defaults
#   ./fetch-kubeconfig.sh <REMOTE_IP>       # custom remote IP, default destination
#   ./fetch-kubeconfig.sh <REMOTE_IP> <DEST_PATH>

remote_user="root"
remote_ip="${1:-10.6.105.126}"
remote_path="/root/ocp/auth/kubeconfig"
destination="${2:-$HOME/Downloads/cnfdc3-kubeconfig}"

# Ensure scp is available
if ! command -v scp >/dev/null 2>&1; then
  echo "Error: scp is not installed or not in PATH" >&2
  exit 1
fi

# Create destination directory if it does not exist
dest_dir="$(dirname "${destination}")"
mkdir -p "${dest_dir}"

echo "Copying kubeconfig from ${remote_user}@${remote_ip}:${remote_path} to ${destination} ..."

scp "${remote_user}@${remote_ip}:${remote_path}" "${destination}"

# Restrict file permissions
chmod 600 "${destination}" || true

echo "Kubeconfig saved to: ${destination}"

