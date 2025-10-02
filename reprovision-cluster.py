#!/usr/bin/env python3
"""
Reprovision cluster via the succulent web form.

This script automates the cluster provisioning process by:
1. Opening the succulent exposeform page
2. Filling in the form with the specified OCP version
3. Submitting the form to create the cluster

Usage Examples:
  ./reprovision-cluster.py 4.17 --email user@redhat.com --kerberos-id user --env cnfdc3
  ./reprovision-cluster.py 4.18 --email user@redhat.com --kerberos-id user --env cnfdc3 --visible
  ./reprovision-cluster.py 4.17 --email user@redhat.com --kerberos-id user --env cnfdc4 --dry-run
  ./reprovision-cluster.py -h                    # Show this help message

Setup:
  python3 -m venv venv
  source venv/bin/activate
  pip install -r requirements.txt
  playwright install chromium
"""

import sys


# Check for virtual environment FIRST, before other imports
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
        print("  playwright install chromium", file=sys.stderr)
        print("\nContinuing anyway...\n", file=sys.stderr)


# Check for virtual environment before any other imports
check_virtualenv()

import argparse
import time
from pathlib import Path

try:
    from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError
except ImportError:
    print("Error: Playwright not found.", file=sys.stderr)
    print("Please install it with:", file=sys.stderr)
    print("  pip install playwright", file=sys.stderr)
    print("  playwright install chromium", file=sys.stderr)
    sys.exit(1)


def reprovision_cluster(ocp_version: str, email: str, kerberos_id: str,
                        headless: bool = True, timeout: int = 30000,
                        dry_run: bool = False, url: str = None) -> bool:
    """
    Automate cluster reprovisioning via the succulent web form.

    Args:
        ocp_version: OCP version tag (e.g., "4.17", "4.18")
        email: Email address for the form
        kerberos_id: Kerberos ID for the form
        headless: Run browser in headless mode (default: True)
        timeout: Timeout for page operations in milliseconds (default: 30000)
        dry_run: Run in dry-run mode (visible browser, no submission)
        url: URL to the provisioning form

    Returns:
        True if successful, False otherwise
    """
    if dry_run:
        print("=" * 70)
        print("DRY RUN MODE - Browser will be visible, form will NOT be submitted")
        print("=" * 70)

    print(f"Starting cluster reprovisioning for OCP version: {ocp_version}")
    print(f"Email: {email}")
    print(f"Kerberos ID: {kerberos_id}")
    print(f"URL: {url}\n")

    try:
        with sync_playwright() as p:
            # Launch browser
            print("Launching browser...")
            browser = p.chromium.launch(
                headless=headless,
                args=[
                    '--ignore-certificate-errors',  # For Red Hat internal SSL certs
                    '--disable-web-security',
                ]
            )

            # Create context with certificate error bypassing
            context = browser.new_context(
                ignore_https_errors=True,  # Ignore SSL certificate errors
                viewport={'width': 1920, 'height': 1080}
            )

            page = context.new_page()

            # Navigate to the form
            print(f"Navigating to {url}...")
            page.goto(url, wait_until='networkidle', timeout=timeout)

            # Give the page a moment to fully load
            time.sleep(2)

            print("Filling in the form...")

            # Fill in email
            try:
                email_field = page.locator('input[name*="email" i], input[id*="email" i], input[placeholder*="email" i]').first
                if email_field.is_visible(timeout=5000):
                    email_field.fill(email)
                    print(f"  ✓ Email: {email}")
            except Exception as e:
                print(f"  ⚠ Could not find email field: {e}")

            # Fill in Kerberos ID
            try:
                kerberos_field = page.locator('input[name*="kerberos" i], input[id*="kerberos" i], input[placeholder*="kerberos" i]').first
                if kerberos_field.is_visible(timeout=5000):
                    kerberos_field.fill(kerberos_id)
                    print(f"  ✓ Kerberos ID: {kerberos_id}")
            except Exception as e:
                print(f"  ⚠ Could not find kerberos field: {e}")

            # Fill in OCP Tag Version (input field: name="parameter_tag", id="tag")
            try:
                # The OCP Tag field is a text input, not a dropdown
                ocp_input = page.locator('input[name="parameter_tag"], input#tag').first
                if ocp_input.is_visible(timeout=5000):
                    # Clear the field first, then fill with the new version
                    ocp_input.clear()
                    ocp_input.fill(ocp_version)
                    print(f"  ✓ OCP Tag Version: {ocp_version}")
                else:
                    print("  ⚠ Could not find OCP Tag input field")
            except Exception as e:
                print(f"  ⚠ Could not set OCP version: {e}")

            # Ensure release version is set to "nightly" (usually default)
            try:
                release_select = page.locator('select[name*="release" i], select[id*="release" i]').first
                if release_select.is_visible(timeout=5000):
                    release_select.select_option(label="nightly")
                    print("  ✓ Release Version: nightly")
            except Exception as e:
                print(f"  ℹ Release version field not found or already set: {e}")

            # Take a screenshot before submission (helpful for debugging)
            screenshot_path = Path.home() / "Downloads" / "reprovision-form-before-submit.png"
            page.screenshot(path=str(screenshot_path))
            print(f"\n  Screenshot saved: {screenshot_path}")

            # Find and click the "Create Cluster" button
            if dry_run:
                print("\n" + "=" * 70)
                print("DRY RUN MODE: Skipping form submission")
                print("=" * 70)
                print("\nBrowser will remain open for 30 seconds for you to inspect...")
                print("Press Ctrl+C to close earlier, or wait for auto-close.")
                try:
                    time.sleep(30)
                except KeyboardInterrupt:
                    print("\nClosing browser...")
                return True

            print("\nLooking for 'Create Cluster' button...")
            try:
                # Try different selectors for the submit button
                create_button = page.locator('button:has-text("Create Cluster"), input[type="submit"][value*="Create" i], button[type="submit"]').first

                if create_button.is_visible(timeout=5000):
                    print("  Found 'Create Cluster' button")

                    # Click the button (no_wait_after since form might use AJAX)
                    create_button.click(no_wait_after=True)
                    print("  ✓ Clicked 'Create Cluster' button!")

                    # Wait a moment for the submission to process
                    time.sleep(3)

                    # Take a screenshot after submission
                    screenshot_path_after = Path.home() / "Downloads" / "reprovision-form-after-submit.png"
                    page.screenshot(path=str(screenshot_path_after))
                    print(f"  Screenshot saved: {screenshot_path_after}")

                    # Check for success message or confirmation
                    try:
                        # Look for common success indicators
                        if page.locator('text=/success|created|submitted/i').first.is_visible(timeout=5000):
                            print("\n✓ Cluster creation request submitted successfully!")
                        else:
                            print("\n✓ Form submitted (check screenshots for confirmation)")
                    except Exception:
                        print("\n✓ Form submitted (check screenshots for confirmation)")

                    return True
                else:
                    print("  ✗ Create Cluster button not visible")
                    return False

            except Exception as e:
                print(f"  ✗ Error clicking Create Cluster button: {e}")
                return False

    except PlaywrightTimeoutError as e:
        print(f"\n✗ Timeout error: {e}", file=sys.stderr)
        print("The page may require authentication or be unreachable.", file=sys.stderr)
        return False
    except Exception as e:
        print(f"\n✗ Error during cluster reprovisioning: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return False
    finally:
        try:
            browser.close()
        except Exception:
            pass


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="""
╔══════════════════════════════════════════════════════════════════╗
║  Cluster Reprovision Automation                                  ║
║  Automate cluster provisioning via succulent web form            ║
╚══════════════════════════════════════════════════════════════════╝

This script will:
  • Navigate to the provisioning form (default: cnfdc3)
  • Fill in the provisioning form with your details
  • Select the specified OCP version
  • Submit the form to create/reprovision the cluster
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 4.17 --email user@redhat.com --kerberos-id user --env cnfdc3
      Provision cnfdc3 cluster with OCP 4.17

  %(prog)s 4.18 --email user@redhat.com --kerberos-id user --env cnfdc3 --visible
      Provision with OCP 4.18 (show browser)

  %(prog)s 4.17 --email user@redhat.com --kerberos-id user --env cnfdc4 --dry-run
      Test run on cnfdc4 - fill form but don't submit (visible)

Setup Instructions:
  1. Create and activate virtual environment:
     python3 -m venv venv
     source venv/bin/activate

  2. Install dependencies:
     pip install -r requirements.txt

  3. Install Playwright browsers:
     playwright install chromium

For more information, see the README.md file.
        """
    )
    parser.add_argument(
        'ocp_version',
        nargs='?',
        metavar='OCP_VERSION',
        help='OCP version tag (e.g., "4.17", "4.18")'
    )
    parser.add_argument(
        '-v', '--version',
        dest='ocp_version_flag',
        metavar='VERSION',
        help='OCP version tag (alternative to positional argument)'
    )
    parser.add_argument(
        '--email',
        required=True,
        metavar='EMAIL',
        help='Email address for the form (e.g., user@redhat.com)'
    )
    parser.add_argument(
        '--kerberos-id',
        required=True,
        metavar='ID',
        help='Kerberos ID for the form (e.g., username)'
    )
    parser.add_argument(
        '--env',
        help='Environment name (e.g., cnfdc3, cnfdc4)'
    )
    parser.add_argument(
        '--url',
        help='Full URL to the provisioning form (overrides --env)'
    )
    parser.add_argument(
        '--headless',
        action='store_true',
        default=True,
        help='Run browser in headless mode (default: enabled)'
    )
    parser.add_argument(
        '--visible',
        action='store_true',
        help='Run browser in visible mode (shows browser window)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Dry run mode: show browser, fill form, but do NOT submit (implies --visible)'
    )
    parser.add_argument(
        '--timeout',
        type=int,
        default=30000,
        metavar='MS',
        help='Timeout for page operations in milliseconds (default: %(default)s)'
    )

    args = parser.parse_args()

    # Determine OCP version
    ocp_version = args.ocp_version or args.ocp_version_flag
    if not ocp_version:
        print("Error: OCP version is required", file=sys.stderr)
        print("Usage: ./reprovision-cluster.py <OCP_VERSION> --email <EMAIL> --kerberos-id <ID> --env <ENV>", file=sys.stderr)
        print("Example: ./reprovision-cluster.py 4.17 --email user@redhat.com --kerberos-id username --env cnfdc3", file=sys.stderr)
        sys.exit(1)

    # Require either --env or --url
    if not args.env and not args.url:
        print("Error: Either --env or --url must be provided", file=sys.stderr)
        print("Usage: ./reprovision-cluster.py 4.17 --email user@redhat.com --kerberos-id username --env cnfdc3", file=sys.stderr)
        sys.exit(1)

    # Construct URL from env if --url not provided
    if args.url:
        url = args.url
    else:
        url = f'https://succulent.eng.redhat.com/exposeform/{args.env}'

    # Determine headless mode (dry-run always forces visible)
    headless = args.headless and not args.visible and not args.dry_run

    # Run the reprovisioning
    success = reprovision_cluster(
        ocp_version=ocp_version,
        email=args.email,
        kerberos_id=args.kerberos_id,
        headless=headless,
        timeout=args.timeout,
        dry_run=args.dry_run,
        url=url
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
