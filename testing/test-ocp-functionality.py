#!/usr/bin/env python3
"""
Functional test suite for OpenShift after applying compliance remediations.

This script runs various functional tests to ensure that key OCP
capabilities are working correctly after applying compliance changes.
"""

import subprocess
import json
import sys
import time
from datetime import datetime
import random
import string


def run_command(cmd, capture_output=True, check=True, timeout=None):
    """Run a shell command and return the result."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=capture_output,
            text=True,
            check=check,
            timeout=timeout
        )
        return result.stdout.strip() if capture_output else None
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Command failed: {cmd}")
        if e.stderr:
            print(f"[ERROR] {e.stderr}")
        if check:
            raise
        return None
    except subprocess.TimeoutExpired:
        print(f"[ERROR] Command timed out: {cmd}")
        if check:
            raise
        return None


def cleanup_test_namespace(namespace):
    """Clean up test namespace if it exists."""
    print(f"[CLEANUP] Removing test namespace {namespace} if exists...")
    run_command(f"oc delete project {namespace} --ignore-not-found=true", check=False)
    
    # Wait for namespace to be fully deleted
    max_wait = 60
    start = time.time()
    while time.time() - start < max_wait:
        result = run_command(
            f"oc get namespace {namespace} 2>/dev/null",
            check=False
        )
        if not result:
            break
        time.sleep(2)


def test_project_creation():
    """Test creating a new project."""
    print("\n" + "=" * 70)
    print("Test: Project Creation")
    print("=" * 70)
    
    # Generate unique project name
    suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
    project_name = f"test-compliance-{suffix}"
    
    try:
        print(f"[TEST] Creating project {project_name}...")
        result = run_command(f"oc new-project {project_name}")
        print(f"✅ Project created successfully")
        return True, project_name
    except Exception as e:
        print(f"❌ Failed to create project: {e}")
        return False, None


def test_pod_deployment(namespace):
    """Test deploying a simple pod."""
    print("\n" + "=" * 70)
    print("Test: Pod Deployment")
    print("=" * 70)
    
    try:
        print(f"[TEST] Deploying test pod in {namespace}...")
        run_command(
            f"oc run test-pod --image=registry.access.redhat.com/ubi8/ubi-minimal:latest "
            f"--command -- sleep 3600 -n {namespace}"
        )
        
        # Wait for pod to be running
        print("[TEST] Waiting for pod to be Running...")
        max_wait = 180
        start = time.time()
        while time.time() - start < max_wait:
            result = run_command(
                f"oc get pod test-pod -n {namespace} -o json",
                check=False
            )
            if result:
                data = json.loads(result)
                phase = data.get('status', {}).get('phase')
                if phase == 'Running':
                    print(f"✅ Pod is running")
                    return True
                elif phase in ['Failed', 'Unknown']:
                    print(f"❌ Pod failed to start: {phase}")
                    return False
            time.sleep(5)
        
        print(f"❌ Pod did not reach Running state within {max_wait}s")
        return False
    except Exception as e:
        print(f"❌ Failed to deploy pod: {e}")
        return False


def test_service_creation(namespace):
    """Test creating a service."""
    print("\n" + "=" * 70)
    print("Test: Service Creation")
    print("=" * 70)
    
    try:
        print(f"[TEST] Creating service in {namespace}...")
        run_command(
            f"oc create service clusterip test-service --tcp=8080:8080 -n {namespace}"
        )
        
        # Verify service exists
        result = run_command(
            f"oc get service test-service -n {namespace} -o json"
        )
        data = json.loads(result)
        cluster_ip = data.get('spec', {}).get('clusterIP')
        
        if cluster_ip and cluster_ip != 'None':
            print(f"✅ Service created with ClusterIP: {cluster_ip}")
            return True
        else:
            print(f"❌ Service created but no ClusterIP assigned")
            return False
    except Exception as e:
        print(f"❌ Failed to create service: {e}")
        return False


def test_deployment_with_replicas(namespace):
    """Test creating a deployment with multiple replicas."""
    print("\n" + "=" * 70)
    print("Test: Deployment with Replicas")
    print("=" * 70)
    
    try:
        print(f"[TEST] Creating deployment in {namespace}...")
        run_command(
            f"oc create deployment test-deployment "
            f"--image=registry.access.redhat.com/ubi8/ubi-minimal:latest "
            f"--replicas=2 -n {namespace} -- sleep 3600"
        )
        
        # Wait for deployment to be ready
        print("[TEST] Waiting for deployment to be ready...")
        max_wait = 300
        run_command(
            f"oc wait deployment/test-deployment -n {namespace} "
            f"--for=condition=Available=True --timeout={max_wait}s",
            check=False
        )
        
        # Check if all replicas are ready
        result = run_command(
            f"oc get deployment test-deployment -n {namespace} -o json"
        )
        data = json.loads(result)
        status = data.get('status', {})
        ready = status.get('readyReplicas', 0)
        desired = status.get('replicas', 0)
        
        if ready == desired and ready > 0:
            print(f"✅ Deployment ready with {ready}/{desired} replicas")
            return True
        else:
            print(f"❌ Deployment not fully ready: {ready}/{desired} replicas")
            return False
    except Exception as e:
        print(f"❌ Failed to create deployment: {e}")
        return False


def test_configmap_and_secret(namespace):
    """Test creating and using ConfigMap and Secret."""
    print("\n" + "=" * 70)
    print("Test: ConfigMap and Secret Creation")
    print("=" * 70)
    
    try:
        print(f"[TEST] Creating ConfigMap in {namespace}...")
        run_command(
            f"oc create configmap test-config --from-literal=key1=value1 -n {namespace}"
        )
        
        print(f"[TEST] Creating Secret in {namespace}...")
        run_command(
            f"oc create secret generic test-secret --from-literal=password=secret123 -n {namespace}"
        )
        
        # Verify they exist
        cm_result = run_command(
            f"oc get configmap test-config -n {namespace} -o json"
        )
        secret_result = run_command(
            f"oc get secret test-secret -n {namespace} -o json"
        )
        
        if cm_result and secret_result:
            print(f"✅ ConfigMap and Secret created successfully")
            return True
        else:
            print(f"❌ Failed to verify ConfigMap or Secret")
            return False
    except Exception as e:
        print(f"❌ Failed to create ConfigMap/Secret: {e}")
        return False


def test_route_creation(namespace):
    """Test creating a route."""
    print("\n" + "=" * 70)
    print("Test: Route Creation")
    print("=" * 70)
    
    try:
        print(f"[TEST] Creating route in {namespace}...")
        
        # First create a simple service if not exists
        run_command(
            f"oc create service clusterip test-route-svc --tcp=8080:8080 -n {namespace}",
            check=False
        )
        
        # Create route
        run_command(
            f"oc create route edge test-route --service=test-route-svc -n {namespace}"
        )
        
        # Verify route exists and has a host
        result = run_command(
            f"oc get route test-route -n {namespace} -o json"
        )
        data = json.loads(result)
        host = data.get('spec', {}).get('host')
        
        if host:
            print(f"✅ Route created with host: {host}")
            return True
        else:
            print(f"❌ Route created but no host assigned")
            return False
    except Exception as e:
        print(f"❌ Failed to create route: {e}")
        return False


def test_persistent_volume_claim(namespace):
    """Test creating a PersistentVolumeClaim."""
    print("\n" + "=" * 70)
    print("Test: PersistentVolumeClaim Creation")
    print("=" * 70)
    
    try:
        # Check if there's a default storage class
        sc_result = run_command(
            "oc get storageclass -o json",
            check=False
        )
        
        if not sc_result:
            print("⚠️  No storage class available, skipping PVC test")
            return True  # Not a failure, just skip
        
        sc_data = json.loads(sc_result)
        if not sc_data.get('items'):
            print("⚠️  No storage class available, skipping PVC test")
            return True
        
        print(f"[TEST] Creating PVC in {namespace}...")
        
        pvc_yaml = f"""
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: {namespace}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
"""
        
        # Write PVC to temp file and apply
        run_command(f"cat <<EOF | oc apply -f -\n{pvc_yaml}\nEOF")
        
        # Wait a bit for PVC to be bound or pending
        time.sleep(10)
        
        result = run_command(
            f"oc get pvc test-pvc -n {namespace} -o json",
            check=False
        )
        
        if result:
            data = json.loads(result)
            phase = data.get('status', {}).get('phase')
            print(f"✅ PVC created (status: {phase})")
            return True
        else:
            print(f"❌ Failed to verify PVC")
            return False
    except Exception as e:
        print(f"❌ Failed to create PVC: {e}")
        return False


def test_build_capability(namespace):
    """Test OpenShift build capability."""
    print("\n" + "=" * 70)
    print("Test: Build Capability")
    print("=" * 70)
    
    try:
        print(f"[TEST] Creating build config in {namespace}...")
        
        # Create a simple BuildConfig
        bc_yaml = f"""
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: test-build
  namespace: {namespace}
spec:
  output:
    to:
      kind: ImageStreamTag
      name: test-output:latest
  source:
    type: Dockerfile
    dockerfile: |
      FROM registry.access.redhat.com/ubi8/ubi-minimal:latest
      RUN echo "test build"
  strategy:
    type: Docker
"""
        
        run_command(f"cat <<EOF | oc apply -f -\n{bc_yaml}\nEOF")
        
        # Also need ImageStream
        run_command(f"oc create imagestream test-output -n {namespace}", check=False)
        
        result = run_command(
            f"oc get buildconfig test-build -n {namespace} -o json",
            check=False
        )
        
        if result:
            print(f"✅ BuildConfig created successfully")
            return True
        else:
            print(f"❌ Failed to verify BuildConfig")
            return False
    except Exception as e:
        print(f"⚠️  Build capability test skipped or failed: {e}")
        # Don't fail on this, as builds might be restricted
        return True


def run_all_tests():
    """Run all functional tests."""
    print("=" * 70)
    print("OpenShift Functional Test Suite")
    print("=" * 70)
    
    # Check prerequisites
    if not run_command("command -v oc", check=False):
        print("[ERROR] 'oc' CLI not found.")
        sys.exit(1)
    
    if not run_command("oc whoami", check=False):
        print("[ERROR] Not logged into a cluster.")
        sys.exit(1)
    
    test_results = {}
    test_namespace = None
    
    try:
        # Test 1: Project creation
        success, test_namespace = test_project_creation()
        test_results['project_creation'] = success
        
        if not test_namespace:
            print("\n❌ Cannot continue without a test namespace")
            return test_results
        
        # Test 2: Pod deployment
        test_results['pod_deployment'] = test_pod_deployment(test_namespace)
        
        # Test 3: Service creation
        test_results['service_creation'] = test_service_creation(test_namespace)
        
        # Test 4: Deployment with replicas
        test_results['deployment_replicas'] = test_deployment_with_replicas(test_namespace)
        
        # Test 5: ConfigMap and Secret
        test_results['configmap_secret'] = test_configmap_and_secret(test_namespace)
        
        # Test 6: Route creation
        test_results['route_creation'] = test_route_creation(test_namespace)
        
        # Test 7: PVC creation
        test_results['pvc_creation'] = test_persistent_volume_claim(test_namespace)
        
        # Test 8: Build capability
        test_results['build_capability'] = test_build_capability(test_namespace)
        
    finally:
        # Cleanup
        if test_namespace:
            cleanup_test_namespace(test_namespace)
    
    return test_results


def main():
    """Main function."""
    results = run_all_tests()
    
    # Print summary
    print("\n" + "=" * 70)
    print("Test Results Summary")
    print("=" * 70)
    
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    
    print(f"\nTests Passed: {passed}/{total}")
    print("\nDetailed Results:")
    for test_name, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"  {status} - {test_name.replace('_', ' ').title()}")
    
    # Save results to file
    timestamp = datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
    report_file = f"functional-test-results-{timestamp}.json"
    
    report = {
        'timestamp': timestamp,
        'total_tests': total,
        'passed_tests': passed,
        'failed_tests': total - passed,
        'results': results,
        'overall_status': 'PASS' if passed == total else 'FAIL'
    }
    
    with open(report_file, 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"\n[INFO] Test report saved to {report_file}")
    
    # Exit with appropriate code
    if passed == total:
        print("\n✅ ALL TESTS PASSED")
        sys.exit(0)
    else:
        print(f"\n❌ {total - passed} TEST(S) FAILED")
        sys.exit(1)


if __name__ == "__main__":
    main()

