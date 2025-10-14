#!/usr/bin/env python3
"""
Capture baseline cluster health metrics before applying compliance remediations.

This script captures the current state of the OpenShift cluster to establish
a baseline for comparison after remediations are applied.
"""

import subprocess
import json
import sys
from datetime import datetime
import os


def run_command(cmd, capture_output=True, check=True):
    """Run a shell command and return the result."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=capture_output,
            text=True,
            check=check
        )
        return result.stdout.strip() if capture_output else None
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Command failed: {cmd}")
        print(f"[ERROR] {e.stderr}")
        if check:
            raise
        return None


def capture_cluster_operators():
    """Capture status of all cluster operators."""
    print("[INFO] Capturing cluster operators status...")
    output = run_command("oc get co -o json")
    data = json.loads(output)
    
    operators = []
    for item in data.get('items', []):
        name = item['metadata']['name']
        conditions = {
            cond['type']: cond['status']
            for cond in item.get('status', {}).get('conditions', [])
        }
        operators.append({
            'name': name,
            'available': conditions.get('Available', 'Unknown'),
            'progressing': conditions.get('Progressing', 'Unknown'),
            'degraded': conditions.get('Degraded', 'Unknown')
        })
    
    return operators


def capture_nodes():
    """Capture node status."""
    print("[INFO] Capturing nodes status...")
    output = run_command("oc get nodes -o json")
    data = json.loads(output)
    
    nodes = []
    for item in data.get('items', []):
        name = item['metadata']['name']
        conditions = {
            cond['type']: cond['status']
            for cond in item.get('status', {}).get('conditions', [])
        }
        nodes.append({
            'name': name,
            'ready': conditions.get('Ready', 'Unknown'),
            'memory_pressure': conditions.get('MemoryPressure', 'Unknown'),
            'disk_pressure': conditions.get('DiskPressure', 'Unknown'),
            'pid_pressure': conditions.get('PIDPressure', 'Unknown')
        })
    
    return nodes


def capture_machine_config_pools():
    """Capture MachineConfigPool status."""
    print("[INFO] Capturing MachineConfigPool status...")
    output = run_command("oc get mcp -o json")
    data = json.loads(output)
    
    mcps = []
    for item in data.get('items', []):
        name = item['metadata']['name']
        status = item.get('status', {})
        conditions = {
            cond['type']: cond['status']
            for cond in status.get('conditions', [])
        }
        mcps.append({
            'name': name,
            'updated': conditions.get('Updated', 'Unknown'),
            'updating': conditions.get('Updating', 'Unknown'),
            'degraded': conditions.get('Degraded', 'Unknown'),
            'machine_count': status.get('machineCount', 0),
            'ready_machine_count': status.get('readyMachineCount', 0),
            'updated_machine_count': status.get('updatedMachineCount', 0)
        })
    
    return mcps


def capture_cluster_version():
    """Capture cluster version info."""
    print("[INFO] Capturing cluster version...")
    output = run_command("oc get clusterversion -o json")
    data = json.loads(output)
    
    if data.get('items'):
        item = data['items'][0]
        status = item.get('status', {})
        conditions = {
            cond['type']: cond['status']
            for cond in status.get('conditions', [])
        }
        return {
            'version': status.get('desired', {}).get('version', 'Unknown'),
            'available': conditions.get('Available', 'Unknown'),
            'progressing': conditions.get('Progressing', 'Unknown'),
            'failing': conditions.get('Failing', 'Unknown')
        }
    return {}


def capture_api_server_health():
    """Check API server health."""
    print("[INFO] Checking API server health...")
    # Check if we can access the API
    result = run_command("oc whoami", check=False)
    api_accessible = result is not None
    
    # Get API server pods status
    output = run_command(
        "oc get pods -n openshift-kube-apiserver -l app=openshift-kube-apiserver -o json",
        check=False
    )
    
    api_pods = []
    if output:
        data = json.loads(output)
        for item in data.get('items', []):
            name = item['metadata']['name']
            status = item.get('status', {})
            api_pods.append({
                'name': name,
                'phase': status.get('phase', 'Unknown'),
                'ready': all(
                    c.get('ready', False)
                    for c in status.get('containerStatuses', [])
                )
            })
    
    return {
        'api_accessible': api_accessible,
        'api_pods': api_pods
    }


def capture_etcd_health():
    """Check etcd health."""
    print("[INFO] Checking etcd health...")
    output = run_command(
        "oc get pods -n openshift-etcd -l app=etcd -o json",
        check=False
    )
    
    etcd_pods = []
    if output:
        data = json.loads(output)
        for item in data.get('items', []):
            name = item['metadata']['name']
            status = item.get('status', {})
            etcd_pods.append({
                'name': name,
                'phase': status.get('phase', 'Unknown'),
                'ready': all(
                    c.get('ready', False)
                    for c in status.get('containerStatuses', [])
                )
            })
    
    return etcd_pods


def capture_critical_namespaces():
    """Capture status of pods in critical namespaces."""
    print("[INFO] Capturing critical namespace pod counts...")
    critical_ns = [
        'openshift-apiserver',
        'openshift-authentication',
        'openshift-console',
        'openshift-monitoring',
        'openshift-ingress',
        'openshift-dns'
    ]
    
    namespace_status = {}
    for ns in critical_ns:
        output = run_command(f"oc get pods -n {ns} -o json", check=False)
        if output:
            data = json.loads(output)
            total = len(data.get('items', []))
            running = sum(
                1 for item in data.get('items', [])
                if item.get('status', {}).get('phase') == 'Running'
            )
            namespace_status[ns] = {
                'total_pods': total,
                'running_pods': running
            }
    
    return namespace_status


def save_baseline(baseline_data, output_file):
    """Save baseline data to a JSON file."""
    with open(output_file, 'w') as f:
        json.dump(baseline_data, f, indent=2)
    print(f"[SUCCESS] Baseline saved to {output_file}")


def main():
    """Main function to capture baseline."""
    print("=" * 70)
    print("OpenShift Cluster Baseline Capture")
    print("=" * 70)
    
    # Check if oc is available
    if not run_command("command -v oc", check=False):
        print("[ERROR] 'oc' CLI not found. Please install and login to your cluster.")
        sys.exit(1)
    
    # Check if we're logged in
    if not run_command("oc whoami", check=False):
        print("[ERROR] Not logged into a cluster. Please run 'oc login' first.")
        sys.exit(1)
    
    timestamp = datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
    
    baseline = {
        'timestamp': timestamp,
        'cluster_operators': capture_cluster_operators(),
        'nodes': capture_nodes(),
        'machine_config_pools': capture_machine_config_pools(),
        'cluster_version': capture_cluster_version(),
        'api_server': capture_api_server_health(),
        'etcd': capture_etcd_health(),
        'critical_namespaces': capture_critical_namespaces()
    }
    
    # Determine output file
    output_file = f"cluster-baseline-{timestamp}.json"
    if len(sys.argv) > 1:
        output_file = sys.argv[1]
    
    save_baseline(baseline, output_file)
    
    # Create a symlink to the latest baseline
    latest_link = "cluster-baseline-latest.json"
    if os.path.exists(latest_link):
        os.remove(latest_link)
    os.symlink(output_file, latest_link)
    print(f"[INFO] Latest baseline symlink created: {latest_link}")
    
    # Print summary
    print("\n" + "=" * 70)
    print("Baseline Summary")
    print("=" * 70)
    
    print(f"\nCluster Operators: {len(baseline['cluster_operators'])}")
    degraded_cos = [
        co['name'] for co in baseline['cluster_operators']
        if co['degraded'] == 'True'
    ]
    if degraded_cos:
        print(f"  ⚠️  Degraded operators: {', '.join(degraded_cos)}")
    
    print(f"\nNodes: {len(baseline['nodes'])}")
    not_ready = [
        node['name'] for node in baseline['nodes']
        if node['ready'] != 'True'
    ]
    if not_ready:
        print(f"  ⚠️  Not ready nodes: {', '.join(not_ready)}")
    
    print(f"\nMachineConfigPools: {len(baseline['machine_config_pools'])}")
    for mcp in baseline['machine_config_pools']:
        print(f"  - {mcp['name']}: {mcp['updated_machine_count']}/{mcp['machine_count']} updated")
    
    print(f"\nCluster Version: {baseline['cluster_version'].get('version', 'Unknown')}")
    
    print("\n" + "=" * 70)


if __name__ == "__main__":
    main()

