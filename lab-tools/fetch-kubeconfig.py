#!/usr/bin/env python3
"""
Fetch kubeconfig from a remote host via scp.

This script:
1. Scrapes the installer IP from the succulent webpage
2. (Optional) Waits for all cluster nodes to be up with IPs assigned
3. Removes any existing SSH host key for that IP
4. Copies the kubeconfig via scp
5. Saves it to ~/Downloads/cnfdc3-kubeconfig with proper permissions

Usage:
  ./fetch-kubeconfig.py --env cnfdc3                  # fetch kubeconfig from cnfdc3
  ./fetch-kubeconfig.py --env cnfdc3 --wait           # wait for cluster ready, then fetch
  ./fetch-kubeconfig.py --env cnfdc4                  # fetch from cnfdc4 environment
  ./fetch-kubeconfig.py <REMOTE_IP>                   # use custom IP (skip scraping)
  ./fetch-kubeconfig.py <REMOTE_IP> <DEST>            # custom IP and destination

Examples:
  ./fetch-kubeconfig.py --env cnfdc3 --wait --max-wait 90       # wait up to 90 minutes
  ./fetch-kubeconfig.py --env cnfdc4 --wait --poll-interval 60  # check every 60 seconds
  ./fetch-kubeconfig.py 10.6.105.126                            # use specific IP
"""

import sys
import os
import subprocess
import argparse
from pathlib import Path
from typing import Optional


def check_virtualenv():
    """
    Check if running in a virtual environment and warn if not.
    """
    in_venv = (
        hasattr(sys, 'real_prefix')
        or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix)
    )

    if not in_venv:
        print("Warning: Not running in a virtual environment!", file=sys.stderr)
        print("It's recommended to use a virtual environment to avoid dependency conflicts.", file=sys.stderr)
        print("\nTo set up a virtual environment:", file=sys.stderr)
        print("  python3 -m venv venv", file=sys.stderr)
        print("  source venv/bin/activate", file=sys.stderr)
        print("  pip install -r requirements.txt", file=sys.stderr)
        print("\nContinuing anyway...\n", file=sys.stderr)


# Check for virtual environment
check_virtualenv()

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("Error: Required dependencies not found.", file=sys.stderr)
    print("Please install them with: pip install -r requirements.txt", file=sys.stderr)
    print("Or manually: pip install requests beautifulsoup4", file=sys.stderr)
    sys.exit(1)


def check_node_status(url: str, verify_ssl: bool = False) -> dict:
    """
    Check the status of all nodes in the cluster.

    Args:
        url: The URL to scrape
        verify_ssl: Whether to verify SSL certificates

    Returns:
        Dictionary with node status information
    """
    import re

    try:
        # For Red Hat internal sites, disable SSL verification and use Kerberos auth if available
        session = requests.Session()

        # Try to use Kerberos authentication if available
        try:
            from requests_kerberos import HTTPKerberosAuth, OPTIONAL
            session.auth = HTTPKerberosAuth(mutual_authentication=OPTIONAL)
        except ImportError:
            pass

        # Disable SSL verification for internal Red Hat sites
        if not verify_ssl:
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

        response = session.get(url, timeout=10, verify=verify_ssl)
        response.raise_for_status()

        soup = BeautifulSoup(response.text, 'html.parser')

        nodes = {}
        installer_ip = None

        # Find table rows with VM information
        tables = soup.find_all('table')
        for table in tables:
            rows = table.find_all('tr')

            # Parse all rows and filter based on content
            for row in rows:
                cells = row.find_all(['td', 'th'])
                if len(cells) >= 2:
                    vm_name = cells[0].get_text().strip()
                    status_or_client = cells[1].get_text().strip()

                    # Skip header rows and plan name rows
                    if vm_name.lower() in ['vm name', 'plan name']:
                        continue

                    # Only process rows where the status is "up" or "down" (VM rows)
                    # This filters out the Plan name table which has "Client" in the 2nd column
                    if status_or_client.lower() not in ['up', 'down']:
                        continue

                    # This is a VM row, get the IP from the 3rd column
                    ip_text = cells[2].get_text().strip() if len(cells) > 2 else ""

                    # Extract IP if present
                    ip_pattern = r'\b(?:\d{1,3}\.){3}\d{1,3}\b'
                    ip_match = re.search(ip_pattern, ip_text)
                    ip = ip_match.group(0) if ip_match else None

                    # Store node info
                    nodes[vm_name] = {
                        'status': status_or_client.lower(),
                        'ip': ip
                    }

                    # Track installer IP
                    if 'installer' in vm_name.lower() and ip:
                        installer_ip = ip

        return {
            'nodes': nodes,
            'installer_ip': installer_ip
        }

    except Exception as e:
        print(f"Error checking node status: {e}", file=sys.stderr)
        return {'nodes': {}, 'installer_ip': None}


def wait_for_cluster_ready(url: str, verify_ssl: bool = False,
                           max_wait_minutes: int = 60,
                           poll_interval: int = 30) -> Optional[str]:
    """
    Wait for all cluster nodes to be up with IPs assigned.

    Args:
        url: The URL to scrape
        verify_ssl: Whether to verify SSL certificates
        max_wait_minutes: Maximum time to wait in minutes
        poll_interval: Seconds between polls

    Returns:
        The installer IP address if successful, None otherwise
    """
    import time

    print("Waiting for cluster nodes to be ready...")
    print(f"Will check {url} every {poll_interval} seconds (max {max_wait_minutes} minutes)\n")

    start_time = time.time()
    max_wait_seconds = max_wait_minutes * 60
    attempt = 0

    while time.time() - start_time < max_wait_seconds:
        attempt += 1
        elapsed = int(time.time() - start_time)
        print(f"[Attempt {attempt}, {elapsed}s elapsed] Checking node status...")

        status = check_node_status(url, verify_ssl)
        nodes = status.get('nodes', {})
        installer_ip = status.get('installer_ip')

        if not nodes:
            print("  ⚠ No nodes found on the page")
            time.sleep(poll_interval)
            continue

        # Analyze node status
        total_nodes = len(nodes)
        up_nodes = sum(1 for n in nodes.values() if n['status'] == 'up')
        nodes_with_ip = sum(1 for n in nodes.values() if n['ip'])

        print(f"  Nodes: {up_nodes}/{total_nodes} up, {nodes_with_ip}/{total_nodes} have IPs")

        # Show details
        for name, info in sorted(nodes.items()):
            status_icon = "✓" if info['status'] == 'up' else "✗"
            ip_info = info['ip'] if info['ip'] else "no IP"
            print(f"    {status_icon} {name}: {info['status']}, {ip_info}")

        # Check if all critical nodes are ready
        # We need at least installer and masters to be up with IPs
        critical_ready = True

        if not installer_ip:
            print("  ⚠ Installer IP not found")
            critical_ready = False

        # Check for any nodes that are down or missing IPs
        for name, info in nodes.items():
            # Skip bootstrap and worker nodes for initial readiness
            if 'bootstrap' in name.lower():
                continue
            if 'worker' in name.lower() and info['status'] != 'up':
                continue  # Workers might come up later

            if info['status'] != 'up':
                critical_ready = False
            elif not info['ip'] and 'worker' not in name.lower():
                critical_ready = False

        if critical_ready and installer_ip:
            print(f"\n✓ Cluster is ready! Installer IP: {installer_ip}")
            return installer_ip

        print(f"  Waiting {poll_interval} seconds before next check...\n")
        time.sleep(poll_interval)

    print(f"\n✗ Timeout: Cluster not ready after {max_wait_minutes} minutes", file=sys.stderr)
    return None


def scrape_installer_ip(url: str, verify_ssl: bool = False,
                        wait_for_ready: bool = False,
                        max_wait_minutes: int = 60,
                        poll_interval: int = 30) -> Optional[str]:
    """
    Scrape the installer machine's IP from the succulent webpage.

    Args:
        url: The URL to scrape
        verify_ssl: Whether to verify SSL certificates (default: False for internal Red Hat sites)
        wait_for_ready: Wait for all nodes to be up with IPs
        max_wait_minutes: Maximum time to wait for cluster ready
        poll_interval: Seconds between checks when waiting

    Returns:
        The installer IP address if found, None otherwise
    """
    if wait_for_ready:
        return wait_for_cluster_ready(url, verify_ssl, max_wait_minutes, poll_interval)

    # Quick fetch without waiting
    print(f"Fetching installer IP from {url} ...")
    status = check_node_status(url, verify_ssl)
    installer_ip = status.get('installer_ip')

    if installer_ip:
        print(f"Found installer IP: {installer_ip}")
    else:
        print("Warning: Could not find installer IP in the webpage", file=sys.stderr)

    return installer_ip


def remove_ssh_host_key(ip: str) -> bool:
    """
    Remove SSH host key for the given IP using ssh-keygen -R.

    Args:
        ip: The IP address to remove from known_hosts

    Returns:
        True if successful or key didn't exist, False on error
    """
    try:
        print(f"Removing SSH host key for {ip} ...")
        result = subprocess.run(
            ['ssh-keygen', '-R', ip],
            capture_output=True,
            text=True
        )
        # ssh-keygen -R returns 0 whether or not the key existed
        # So we just check if the command ran successfully
        if result.returncode != 0:
            print(f"Warning: ssh-keygen -R failed: {result.stderr}", file=sys.stderr)
            return False
        return True
    except FileNotFoundError:
        print("Error: ssh-keygen not found in PATH", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Error running ssh-keygen: {e}", file=sys.stderr)
        return False


def fetch_kubeconfig(remote_ip: str, remote_user: str = "root",
                     remote_path: str = "/root/ocp/auth/kubeconfig",
                     destination: Optional[str] = None) -> bool:
    """
    Fetch kubeconfig from remote host via scp.

    Args:
        remote_ip: IP address of remote host
        remote_user: Remote username (default: root)
        remote_path: Path to kubeconfig on remote host
        destination: Local destination path (default: ~/Downloads/cnfdc3-kubeconfig)

    Returns:
        True if successful, False otherwise
    """
    # Set default destination if not provided
    if destination is None:
        destination = str(Path.home() / "Downloads" / "cnfdc3-kubeconfig")

    # Ensure destination directory exists
    dest_path = Path(destination)
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    # Check if scp is available
    try:
        subprocess.run(['which', 'scp'], capture_output=True, check=True)
    except subprocess.CalledProcessError:
        print("Error: scp is not installed or not in PATH", file=sys.stderr)
        return False

    # Construct scp command
    remote_location = f"{remote_user}@{remote_ip}:{remote_path}"

    print(f"Copying kubeconfig from {remote_location} to {destination} ...")

    try:
        # Run scp with StrictHostKeyChecking=no to auto-accept new host keys
        result = subprocess.run(
            ['scp', '-o', 'StrictHostKeyChecking=no',
             '-o', 'UserKnownHostsFile=/dev/null',
             remote_location, destination],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            print(f"Error: scp failed: {result.stderr}", file=sys.stderr)
            return False

        # Restrict file permissions
        try:
            os.chmod(destination, 0o600)
        except Exception as e:
            print(f"Warning: Could not set file permissions: {e}", file=sys.stderr)

        print(f"Kubeconfig saved to: {destination}")
        return True

    except Exception as e:
        print(f"Error running scp: {e}", file=sys.stderr)
        return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Fetch kubeconfig from remote host via scp",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        'remote_ip',
        nargs='?',
        help='Remote IP address (if not provided, will scrape from succulent)'
    )
    parser.add_argument(
        'destination',
        nargs='?',
        help='Destination path (default: ~/Downloads/{env}-kubeconfig)'
    )
    parser.add_argument(
        '--env',
        help='Environment name (e.g., cnfdc3, cnfdc4)'
    )
    parser.add_argument(
        '--url',
        help='Full URL to scrape for installer IP (overrides --env)'
    )
    parser.add_argument(
        '--user',
        default='root',
        help='Remote user (default: %(default)s)'
    )
    parser.add_argument(
        '--path',
        default='/root/ocp/auth/kubeconfig',
        help='Remote kubeconfig path (default: %(default)s)'
    )
    parser.add_argument(
        '--verify-ssl',
        action='store_true',
        help='Verify SSL certificates (default: disabled for Red Hat internal sites)'
    )
    parser.add_argument(
        '--wait',
        action='store_true',
        help='Wait for all cluster nodes to be up with IPs before fetching kubeconfig'
    )
    parser.add_argument(
        '--max-wait',
        type=int,
        default=60,
        metavar='MINUTES',
        help='Maximum time to wait for cluster ready in minutes (default: %(default)s)'
    )
    parser.add_argument(
        '--poll-interval',
        type=int,
        default=30,
        metavar='SECONDS',
        help='Seconds between status checks when waiting (default: %(default)s)'
    )

    args = parser.parse_args()

    # Determine remote IP
    if args.remote_ip:
        remote_ip = args.remote_ip
        print(f"Using provided IP: {remote_ip}")

        # Set default destination if not provided
        destination = args.destination
        if not destination:
            env_name = args.env if args.env else 'cluster'
            destination = str(Path.home() / "Downloads" / f"{env_name}-kubeconfig")
    else:
        # If scraping, require either --env or --url
        if not args.env and not args.url:
            print("Error: Either --env or --url must be provided when scraping IP", file=sys.stderr)
            print("Usage: ./fetch-kubeconfig.py --env cnfdc3 [--wait]", file=sys.stderr)
            print("   Or: ./fetch-kubeconfig.py <REMOTE_IP>", file=sys.stderr)
            sys.exit(1)

        # Construct URL from env if --url not provided
        if args.url:
            url = args.url
            env_name = args.env if args.env else 'cluster'
        else:
            url = f'https://succulent.eng.redhat.com/infoplan/{args.env}'
            env_name = args.env

        # Set default destination if not provided
        destination = args.destination
        if not destination:
            destination = str(Path.home() / "Downloads" / f"{env_name}-kubeconfig")

        remote_ip = scrape_installer_ip(
            url,
            verify_ssl=args.verify_ssl,
            wait_for_ready=args.wait,
            max_wait_minutes=args.max_wait,
            poll_interval=args.poll_interval
        )
        if not remote_ip:
            print("Error: Could not determine installer IP", file=sys.stderr)
            print("Please provide IP manually: ./fetch-kubeconfig.py <IP>", file=sys.stderr)
            sys.exit(1)

    # Remove old SSH host key
    remove_ssh_host_key(remote_ip)

    # Fetch kubeconfig
    success = fetch_kubeconfig(
        remote_ip=remote_ip,
        remote_user=args.user,
        remote_path=args.path,
        destination=destination
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
