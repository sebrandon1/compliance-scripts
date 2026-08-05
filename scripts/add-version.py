#!/usr/bin/env python3
"""
Scaffold dashboard files for a new OCP version.

Copies version pages, group pages, and tracking data from an existing
source version to a new target version, updating all version references.

Usage:
  python3 scripts/add-version.py --source 5.0 --target 5.1
  python3 scripts/add-version.py --source 5.0 --target 5.1 --dry-run
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys


def version_slug(version: str) -> str:
    return version.replace(".", "_")


def copy_version_pages(
    source: str, target: str, docs_dir: str, dry_run: bool
) -> list[str]:
    """Copy and update version landing page and subdirectory."""
    created = []

    src_page = os.path.join(docs_dir, "versions", f"{source}.md")
    dst_page = os.path.join(docs_dir, "versions", f"{target}.md")
    if not os.path.exists(src_page):
        print(f"Error: Source version page not found: {src_page}",
              file=sys.stderr)
        sys.exit(1)

    if os.path.exists(dst_page):
        print(f"  Skipping {dst_page} (already exists)")
    else:
        if not dry_run:
            with open(src_page) as f:
                content = f.read()
            content = _replace_version(content, source, target)
            with open(dst_page, 'w') as f:
                f.write(content)
        created.append(dst_page)
        print(f"  Created {dst_page}")

    src_dir = os.path.join(docs_dir, "versions", source)
    dst_dir = os.path.join(docs_dir, "versions", target)
    if not os.path.isdir(src_dir):
        print(f"Error: Source version directory not found: {src_dir}",
              file=sys.stderr)
        sys.exit(1)

    if os.path.isdir(dst_dir):
        print(f"  Skipping {dst_dir}/ (already exists)")
    else:
        if not dry_run:
            shutil.copytree(src_dir, dst_dir)
        print(f"  Copied {src_dir}/ -> {dst_dir}/")

    if not dry_run and os.path.isdir(dst_dir):
        for root, _, files in os.walk(dst_dir):
            for fname in files:
                if fname.endswith('.md'):
                    fpath = os.path.join(root, fname)
                    with open(fpath) as f:
                        content = f.read()
                    updated = _replace_version(content, source, target)
                    if updated != content:
                        with open(fpath, 'w') as f:
                            f.write(updated)
                        created.append(fpath)

    file_count = sum(
        len(files)
        for _, _, files in os.walk(
            dst_dir if os.path.isdir(dst_dir) else src_dir
        )
    )
    print(f"  Updated version references in {file_count} files")

    return created


def _replace_version(content: str, source: str, target: str) -> str:
    """Replace version references in file content."""
    replacements = [
        (f'version: "{source}"', f'version: "{target}"'),
        (f"OCP {source}", f"OCP {target}"),
        (f"ocp-{version_slug(source)}", f"ocp-{version_slug(target)}"),
        (f"compliance/{source}/", f"compliance/{target}/"),
        (f"/{source}/", f"/{target}/"),
        (f"../{source}.html", f"../{target}.html"),
        (f"versions/{source}", f"versions/{target}"),
    ]
    for old, new in replacements:
        content = content.replace(old, new)
    return content


def create_tracking(
    source: str, target: str, data_dir: str, dry_run: bool
) -> str | None:
    """Create version-specific tracking file with reset statuses."""
    src_slug = version_slug(source)
    dst_slug = version_slug(target)

    src_tracking = os.path.join(data_dir, f"tracking-{src_slug}.json")
    if not os.path.exists(src_tracking):
        src_tracking = os.path.join(data_dir, "tracking.json")
    if not os.path.exists(src_tracking):
        print(f"Error: No tracking file found for {source}",
              file=sys.stderr)
        sys.exit(1)

    dst_tracking = os.path.join(data_dir, f"tracking-{dst_slug}.json")
    if os.path.exists(dst_tracking):
        print(f"  Skipping {dst_tracking} (already exists)")
        return None

    with open(src_tracking) as f:
        data = json.load(f)

    for group in data.get("groups", {}).values():
        group["status"] = "pending"
        for field in ["status_note", "jira", "jira_status",
                      "pr", "pr_state", "last_sync"]:
            group[field] = None
        if group.get("compare"):
            group["compare"] = group["compare"].replace(
                f"compliance/{source}/", f"compliance/{target}/"
            )

    meta = data.get("meta", {})
    for field in ["epic", "last_sync", "last_upstream_audit",
                  "upstream_audit_note"]:
        meta[field] = None

    if not dry_run:
        with open(dst_tracking, 'w') as f:
            json.dump(data, f, indent=2)
            f.write('\n')

    print(f"  Created {dst_tracking}")
    print(f"  Reset {len(data.get('groups', {}))} groups to 'pending'")
    return dst_tracking


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Scaffold dashboard files for a new OCP version"
    )
    parser.add_argument(
        "--source", required=True,
        help="Source OCP version to copy from (e.g., 5.0)"
    )
    parser.add_argument(
        "--target", required=True,
        help="Target OCP version to create (e.g., 5.1)"
    )
    parser.add_argument(
        "--docs-dir", default="docs",
        help="Path to docs directory (default: docs)"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be created without writing files"
    )
    args = parser.parse_args()

    if args.dry_run:
        print("DRY RUN - no files will be created\n")

    data_dir = os.path.join(args.docs_dir, "_data")
    if not os.path.isdir(data_dir):
        print(f"Error: Data directory not found: {data_dir}",
              file=sys.stderr)
        sys.exit(1)

    # Validate source version exists
    src_page = os.path.join(args.docs_dir, "versions", f"{args.source}.md")
    if not os.path.exists(src_page):
        print(
            f"Error: Source version {args.source} not found "
            f"(missing {src_page})",
            file=sys.stderr
        )
        sys.exit(1)

    # Validate target doesn't fully exist
    dst_page = os.path.join(args.docs_dir, "versions", f"{args.target}.md")
    dst_dir = os.path.join(args.docs_dir, "versions", args.target)
    dst_slug = version_slug(args.target)
    dst_tracking = os.path.join(data_dir, f"tracking-{dst_slug}.json")
    if (os.path.exists(dst_page) and os.path.isdir(dst_dir)
            and os.path.exists(dst_tracking)):
        print(
            f"Version {args.target} already fully scaffolded. "
            f"Nothing to do."
        )
        return

    print(f"Scaffolding OCP {args.target} from {args.source}...\n")

    print("Step 1: Version pages")
    copy_version_pages(
        args.source, args.target, args.docs_dir, args.dry_run
    )

    print("\nStep 2: Tracking data")
    create_tracking(
        args.source, args.target, data_dir, args.dry_run
    )

    print(f"\nDone! OCP {args.target} scaffolded.")
    print("\nNext steps:")
    print(f"  1. Update RHCOS version in "
          f"docs/versions/{args.target}/remediations.md")
    print(f"  2. Run scans: make export-compliance "
          f"OCP_VERSION={args.target}")
    print("  3. Validate: make validate-dashboard-data")
    print("  4. Commit and push")


if __name__ == "__main__":
    main()
