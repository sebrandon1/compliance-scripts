#!/bin/bash
# compare-clusters.sh - Compare two OpenShift clusters to identify permission differences
# Usage: ./compare-clusters.sh <crc-kubeconfig> <remote-kubeconfig>

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <crc-kubeconfig> <remote-kubeconfig>"
    echo "Example: $0 ~/.crc/machines/crc/kubeconfig ~/Downloads/cnfdc3-kubeconfig"
    exit 1
fi

CRC_KUBECONFIG="$1"
REMOTE_KUBECONFIG="$2"

echo "=========================================="
echo "CRC vs Remote Cluster Comparison"
echo "=========================================="
echo ""

# Function to run command on both clusters
compare() {
    local description="$1"
    local command="$2"
    
    echo "### $description"
    echo ""
    
    echo "CRC:"
    KUBECONFIG="$CRC_KUBECONFIG" bash -c "$command" 2>&1 || echo "  [ERROR]"
    echo ""
    
    echo "Remote:"
    KUBECONFIG="$REMOTE_KUBECONFIG" bash -c "$command" 2>&1 || echo "  [ERROR]"
    echo ""
    echo "---"
    echo ""
}

# 1. OpenShift Version
compare "OpenShift Version" "oc version --short 2>/dev/null | head -2"

# 2. SELinux Status
compare "SELinux Enforcement" "oc debug node/\$(oc get nodes -o name | head -1 | cut -d/ -f2) -- chroot /host getenforce 2>/dev/null || echo 'Cannot determine'"

# 3. SCC Priorities
compare "SCC Priorities" "oc get scc -o custom-columns=NAME:.metadata.name,PRIORITY:.priority,ALLOW-PRIV:.allowPrivilegedContainer,RUN-AS-USER:.runAsUser.type --no-headers | sort -k2 -n"

# 4. Who can use privileged SCC
compare "Users/Groups with Privileged SCC" "oc describe scc privileged | grep -A5 'Users:' | head -6"

# 5. Who can use anyuid SCC
compare "Users/Groups with Anyuid SCC" "oc describe scc anyuid | grep -A5 'Users:' | head -6"

# 6. Default Storage Class
compare "Default StorageClass" "oc get sc -o custom-columns=NAME:.metadata.name,PROVISIONER:.provisioner,DEFAULT:.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class --no-headers"

# 7. Compliance Operator (if installed)
compare "Compliance Operator Version" "oc get csv -n openshift-compliance -o custom-columns=NAME:.metadata.name,VERSION:.spec.version --no-headers 2>/dev/null || echo 'Not installed'"

# 8. Compliance Operator Env Vars (if installed)
compare "Compliance Operator Environment" "oc get deployment compliance-operator -n openshift-compliance -o jsonpath='{.spec.template.spec.containers[0].env[*].name}{\"\n\"}' 2>/dev/null | tr ' ' '\n' || echo 'Not installed'"

# 9. Check if system:serviceaccounts has broad permissions
compare "system:serviceaccounts Permissions" "oc describe scc privileged | grep 'system:serviceaccounts' || echo 'Not granted'; oc describe scc anyuid | grep 'system:serviceaccounts' || echo 'Not granted'"

# 10. Profile Parser Pod Security (if running)
compare "Profile Parser Pod SCC" "oc get pod -n openshift-compliance -l app=profileparser -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.metadata.annotations.openshift\\.io/scc}{\"\\n\"}{end}' 2>/dev/null || echo 'Not running'"

echo "=========================================="
echo "Comparison Complete"
echo "=========================================="
echo ""
echo "Key things to look for:"
echo "  1. SELinux: Enforcing vs Permissive"
echo "  2. SCC priorities: anyuid vs privileged"
echo "  3. Group permissions: system:serviceaccounts"
echo "  4. Actual SCC assignments on pods"

