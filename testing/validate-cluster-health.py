#!/usr/bin/env python3
"""
Validate cluster health after applying compliance remediations.

This script compares the current cluster state against a baseline
and reports any degradations or issues.
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


def load_baseline(baseline_file):
    """Load baseline data from JSON file."""
    if not os.path.exists(baseline_file):
        print(f"[ERROR] Baseline file not found: {baseline_file}")
        sys.exit(1)
    
    with open(baseline_file, 'r') as f:
        return json.load(f)


def get_current_cluster_operators():
    """Get current cluster operators status."""
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
    
    return {op['name']: op for op in operators}


def get_current_nodes():
    """Get current nodes status."""
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
    
    return {node['name']: node for node in nodes}


def get_current_mcps():
    """Get current MachineConfigPool status."""
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
    
    return {mcp['name']: mcp for mcp in mcps}


def validate_cluster_operators(baseline, current):
    """Validate cluster operators against baseline."""
    print("\n" + "=" * 70)
    print("Cluster Operators Validation")
    print("=" * 70)
    
    baseline_cos = {co['name']: co for co in baseline['cluster_operators']}
    issues = []
    warnings = []
    
    for name, current_co in current.items():
        baseline_co = baseline_cos.get(name)
        
        # Check if operator is degraded
        if current_co['degraded'] == 'True':
            if baseline_co and baseline_co['degraded'] != 'True':
                issues.append(f"❌ {name}: became DEGRADED")
            else:
                warnings.append(f"⚠️  {name}: already degraded in baseline")
        
        # Check if operator is not available
        if current_co['available'] != 'True':
            if baseline_co and baseline_co['available'] == 'True':
                issues.append(f"❌ {name}: became UNAVAILABLE")
            else:
                warnings.append(f"⚠️  {name}: already unavailable in baseline")
        
        # Check if operator is progressing for too long (this is a warning, not critical)
        if current_co['progressing'] == 'True':
            warnings.append(f"⚠️  {name}: progressing")
    
    if issues:
        print("\n🔴 CRITICAL ISSUES:")
        for issue in issues:
            print(f"  {issue}")
    
    if warnings:
        print("\n🟡 WARNINGS:")
        for warning in warnings:
            print(f"  {warning}")
    
    if not issues and not warnings:
        print("\n✅ All cluster operators healthy")
    
    return len(issues) == 0, issues, warnings


def validate_nodes(baseline, current):
    """Validate nodes against baseline."""
    print("\n" + "=" * 70)
    print("Nodes Validation")
    print("=" * 70)
    
    baseline_nodes = {node['name']: node for node in baseline['nodes']}
    issues = []
    warnings = []
    
    for name, current_node in current.items():
        baseline_node = baseline_nodes.get(name)
        
        # Check if node is not ready
        if current_node['ready'] != 'True':
            if baseline_node and baseline_node['ready'] == 'True':
                issues.append(f"❌ {name}: became NOT READY")
            else:
                warnings.append(f"⚠️  {name}: already not ready in baseline")
        
        # Check for pressure conditions
        for pressure_type in ['memory_pressure', 'disk_pressure', 'pid_pressure']:
            if current_node[pressure_type] == 'True':
                if baseline_node and baseline_node[pressure_type] != 'True':
                    warnings.append(
                        f"⚠️  {name}: new {pressure_type.replace('_', ' ').title()}"
                    )
    
    # Check for missing nodes
    missing_nodes = set(baseline_nodes.keys()) - set(current.keys())
    for node in missing_nodes:
        issues.append(f"❌ Node {node}: MISSING from cluster")
    
    if issues:
        print("\n🔴 CRITICAL ISSUES:")
        for issue in issues:
            print(f"  {issue}")
    
    if warnings:
        print("\n🟡 WARNINGS:")
        for warning in warnings:
            print(f"  {warning}")
    
    if not issues and not warnings:
        print("\n✅ All nodes healthy")
    
    return len(issues) == 0, issues, warnings


def validate_mcps(baseline, current):
    """Validate MachineConfigPools against baseline."""
    print("\n" + "=" * 70)
    print("MachineConfigPools Validation")
    print("=" * 70)
    
    baseline_mcps = {mcp['name']: mcp for mcp in baseline['machine_config_pools']}
    issues = []
    warnings = []
    
    for name, current_mcp in current.items():
        baseline_mcp = baseline_mcps.get(name)
        
        # Check if MCP is degraded
        if current_mcp['degraded'] == 'True':
            if baseline_mcp and baseline_mcp['degraded'] != 'True':
                issues.append(f"❌ {name}: became DEGRADED")
            else:
                warnings.append(f"⚠️  {name}: already degraded in baseline")
        
        # Check if all machines are updated
        if current_mcp['updated_machine_count'] != current_mcp['machine_count']:
            warnings.append(
                f"⚠️  {name}: {current_mcp['updated_machine_count']}/{current_mcp['machine_count']} machines updated"
            )
        
        # Check if MCP is still updating
        if current_mcp['updating'] == 'True':
            warnings.append(f"⚠️  {name}: still updating")
    
    if issues:
        print("\n🔴 CRITICAL ISSUES:")
        for issue in issues:
            print(f"  {issue}")
    
    if warnings:
        print("\n🟡 WARNINGS:")
        for warning in warnings:
            print(f"  {warning}")
    
    if not issues and not warnings:
        print("\n✅ All MachineConfigPools healthy")
    
    return len(issues) == 0, issues, warnings


def validate_api_accessibility():
    """Validate API server is accessible."""
    print("\n" + "=" * 70)
    print("API Server Validation")
    print("=" * 70)
    
    result = run_command("oc whoami", check=False)
    if result:
        print("✅ API server accessible")
        return True, []
    else:
        print("❌ API server NOT accessible")
        return False, ["API server not accessible"]


def generate_report(baseline, validation_results, output_file):
    """Generate a detailed validation report."""
    report = {
        'timestamp': datetime.utcnow().strftime('%Y%m%dT%H%M%SZ'),
        'baseline_timestamp': baseline['timestamp'],
        'validation_results': validation_results,
        'overall_status': 'PASS' if all(
            r['passed'] for r in validation_results.values()
        ) else 'FAIL'
    }
    
    with open(output_file, 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"\n[INFO] Validation report saved to {output_file}")


def main():
    """Main validation function."""
    print("=" * 70)
    print("OpenShift Cluster Health Validation")
    print("=" * 70)
    
    # Check if oc is available
    if not run_command("command -v oc", check=False):
        print("[ERROR] 'oc' CLI not found. Please install and login to your cluster.")
        sys.exit(1)
    
    # Check if we're logged in
    if not run_command("oc whoami", check=False):
        print("[ERROR] Not logged into a cluster. Please run 'oc login' first.")
        sys.exit(1)
    
    # Load baseline
    baseline_file = "cluster-baseline-latest.json"
    if len(sys.argv) > 1:
        baseline_file = sys.argv[1]
    
    print(f"[INFO] Loading baseline from {baseline_file}")
    baseline = load_baseline(baseline_file)
    print(f"[INFO] Baseline captured at: {baseline['timestamp']}")
    
    # Get current state
    print("\n[INFO] Gathering current cluster state...")
    current_cos = get_current_cluster_operators()
    current_nodes = get_current_nodes()
    current_mcps = get_current_mcps()
    
    # Validate
    validation_results = {}
    
    # API accessibility
    api_passed, api_issues = validate_api_accessibility()
    validation_results['api_server'] = {
        'passed': api_passed,
        'issues': api_issues,
        'warnings': []
    }
    
    # Cluster operators
    co_passed, co_issues, co_warnings = validate_cluster_operators(
        baseline, current_cos
    )
    validation_results['cluster_operators'] = {
        'passed': co_passed,
        'issues': co_issues,
        'warnings': co_warnings
    }
    
    # Nodes
    nodes_passed, node_issues, node_warnings = validate_nodes(
        baseline, current_nodes
    )
    validation_results['nodes'] = {
        'passed': nodes_passed,
        'issues': node_issues,
        'warnings': node_warnings
    }
    
    # MCPs
    mcp_passed, mcp_issues, mcp_warnings = validate_mcps(
        baseline, current_mcps
    )
    validation_results['machine_config_pools'] = {
        'passed': mcp_passed,
        'issues': mcp_issues,
        'warnings': mcp_warnings
    }
    
    # Generate report
    timestamp = datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
    report_file = f"cluster-validation-{timestamp}.json"
    generate_report(baseline, validation_results, report_file)
    
    # Print final summary
    print("\n" + "=" * 70)
    print("Validation Summary")
    print("=" * 70)
    
    all_passed = all(r['passed'] for r in validation_results.values())
    
    if all_passed:
        print("\n✅ VALIDATION PASSED - Cluster appears healthy")
        print("   No critical issues detected after remediation")
        sys.exit(0)
    else:
        print("\n❌ VALIDATION FAILED - Critical issues detected")
        print("   Review the issues above and the validation report")
        
        total_issues = sum(len(r['issues']) for r in validation_results.values())
        total_warnings = sum(len(r['warnings']) for r in validation_results.values())
        
        print(f"\n   Total critical issues: {total_issues}")
        print(f"   Total warnings: {total_warnings}")
        sys.exit(1)


if __name__ == "__main__":
    main()

