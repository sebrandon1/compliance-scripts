#!/usr/bin/env python3
"""
Combine MachineConfig remediations by file path.

This script merges multiple MachineConfig YAML files that target the same
file path into a single combined MachineConfig.
"""
import os
import sys
import urllib.parse
import argparse
from collections import defaultdict

# Check for required dependencies
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed.", file=sys.stderr)
    print("Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


def safe_shortname(path):
    """Convert a file path to a safe shortname for filenames."""
    import re
    # Get the basename (final component) of the path
    basename = os.path.basename(path)

    # For audit rules files, extract the meaningful part
    if 'audit' in path and basename.startswith('75-'):
        # Extract the meaningful part after '75-' and before any file extension
        match = re.match(r'75-(.+?)(?:\.rules)?$', basename)
        if match:
            return f"75-{match.group(1)}"

    # For other files, clean up the basename
    # Remove file extensions and sanitize
    name = re.sub(r'\.[^.]+$', '', basename)  # Remove extension
    name = re.sub(r'[^a-zA-Z0-9\-_]', '-', name)  # Replace special chars with hyphens
    name = re.sub(r'-+', '-', name)  # Collapse multiple hyphens
    return name.strip('-')


def parse_machineconfig_files(src_dir):
    """Parse all MachineConfig YAMLs under src_dir (recursively) and group by
    (file path, severity), where severity is inferred from directory names
    containing one of: high, medium, low. If none found, severity is None.
    """
    combo_map = defaultdict(list)  # (path, severity) -> list of (source_file, decoded_lines)

    severity_names = {"high", "medium", "low"}

    for root, dirs, files in os.walk(src_dir):
        # Skip the combo subdir if present
        dirs[:] = [d for d in dirs if d != 'combo']

        # Determine severity from the relative root path segments
        rel_root = os.path.relpath(root, src_dir)
        parts = [p.lower() for p in rel_root.split(os.sep) if p not in (".", "")]
        severity = None
        for p in parts:
            if p in severity_names:
                severity = p
                break

        for fname in files:
            if not fname.endswith('.yaml'):
                continue
            fpath = os.path.join(root, fname)
            if not os.path.isfile(fpath):
                continue
            with open(fpath) as f:
                docs = list(yaml.safe_load_all(f))
            for doc in docs:
                if not doc or doc.get('kind') != 'MachineConfig':
                    continue
                files = doc.get('spec', {}).get('config', {}).get('storage', {}) \
                    .get('files', [])
                for file_entry in files:
                    path = file_entry.get('path')
                    source = file_entry.get('contents', {}).get('source')
                    if path and source and source.startswith('data:,'):
                        decoded = urllib.parse.unquote(source[6:])
                        lines = [line for line in decoded.splitlines() if line.strip()]
                        combo_map[(path, severity)].append((os.path.relpath(fpath, src_dir), lines))
    return combo_map


def write_combo_yaml(path, severity, sources, out_dir, header_mode="none"):
    """Write a combined MachineConfig YAML for a given file path and severity.
    Sources is a list of (source_file, decoded_lines).
    """
    all_lines = set()
    for _, lines in sources:
        all_lines.update(lines)
    deduped_lines = sorted(all_lines)
    shortname = safe_shortname(path)
    if severity:
        outname = f"{shortname}-{severity}-combo.yaml"
    else:
        outname = f"{shortname}-combo.yaml"
    outpath = os.path.join(out_dir, outname)
    with open(outpath, "w") as out:
        # Optional top-of-file header
        if header_mode and header_mode != "none":
            if header_mode == "provenance":
                out.write(
                    f"# Combined from {len(sources)} remediations for {path}"
                    f"{' | severity: ' + severity if severity else ''}.\n"
                )
            elif header_mode == "full":
                out.write(
                    "# Combined from the following remediations "
                    f"for {path} (all roles){' | severity: ' + severity if severity else ''}:\n"
                )
                for src, _ in sources:
                    out.write(f"#   - {src}\n")
        out.write(
            "apiVersion: machineconfiguration.openshift.io/v1\n"
            "kind: MachineConfig\n"
            "spec:\n"
            "  config:\n"
            "    ignition:\n"
            "      version: 3.5.0\n"
            "    storage:\n"
            "      files:\n"
            "        - contents:\n"
            "            # The following lines are the deduplicated, combined "
            "plaintext contents from all related MachineConfig remediations.\n"
        )
        for line in deduped_lines:
            out.write(f"            # {line}\n")
        out.write("            source: data:,")
        encoded = urllib.parse.quote(
            "\n".join(deduped_lines) + "\n", safe='')
        out.write(encoded)
        out.write(
            """
          mode: 384
          overwrite: true
          path: {path}
""".format(path=path)
        )
    print(f"Wrote {outpath}")


def move_originals_to_combo(combo_map, src_dir, combo_dir):
    """Move original YAMLs that were combined to the
        combo subfolder."""
    moved = set()
    for (_path, _severity), sources in combo_map.items():
        if len(sources) < 2:
            continue
        for src, _ in sources:
            if src in moved:
                continue
            src_path = os.path.join(src_dir, src)
            if os.path.exists(src_path):
                # Ensure destination subdirs exist inside combo_dir to preserve structure
                dest_path = os.path.join(combo_dir, src)
                os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                os.rename(src_path, dest_path)
                moved.add(src)
    if moved:
        print(f"Moved original remediations to {combo_dir}/ "
              f"(only those used in combos)")
    else:
        print("No originals needed to be moved.")


def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description="Combine OpenShift MachineConfig remediations by file path, "
                    "deduplicating contents. By default, moves originals to a subfolder.",
        epilog="""
Examples:
  # Combine all MachineConfigs (default behavior - moves originals)
  %(prog)s --src-dir complianceremediations --out-dir complianceremediations

  # Combine without moving originals (idempotent - safe to run multiple times)
  %(prog)s --src-dir complianceremediations --out-dir complianceremediations --no-move

  # Preview what would be combined without making changes
  %(prog)s --src-dir complianceremediations --dry-run

  # Combine only high severity remediations
  %(prog)s -s high --no-move
"""
    )
    parser.add_argument(
        '--src-dir', default='complianceremediations',
        help='Source directory containing MachineConfig YAMLs '
             '(default: complianceremediations)'
    )
    parser.add_argument(
        '--out-dir', default='complianceremediations',
        help='Directory to write combined YAMLs (default: complianceremediations)'
    )
    parser.add_argument(
        '-s', '--severity', default=None,
        help='Comma-separated severities to include (case-insensitive): high,medium,low'
    )
    parser.add_argument(
        '--header', default='none', choices=['none', 'provenance', 'full'],
        help="Top-of-file header mode for generated files: 'none' (default), 'provenance' (one-line), or 'full' (list sources)"
    )
    parser.add_argument(
        '--no-move', action='store_true',
        help="Don't move original files to combo/ folder (makes script idempotent)"
    )
    parser.add_argument(
        '--dry-run', action='store_true',
        help="Preview what would be combined without making any changes"
    )
    args = parser.parse_args()

    src_dir = args.src_dir
    out_dir = args.out_dir
    # Parse and validate optional severity filter
    severity_filter = None
    if args.severity:
        raw = args.severity.strip().lower().replace(' ', '')
        requested = [s for s in raw.split(',') if s]
        valid = {"high", "medium", "low"}
        invalid = [s for s in requested if s not in valid]
        if invalid:
            raise SystemExit(
                f"Invalid severity value(s): {','.join(invalid)}. Allowed: high, medium, low"
            )
        severity_filter = set(requested)
    combo_dir = os.path.join(src_dir, "combo")

    if args.dry_run:
        print("[DRY-RUN] Preview mode - no files will be modified")
    else:
        os.makedirs(combo_dir, exist_ok=True)
        os.makedirs(out_dir, exist_ok=True)

    # Parse and group MachineConfig YAMLs by (file path, severity)
    combo_map = parse_machineconfig_files(src_dir)
    # If a severity filter is provided, reduce the map to only those severities
    if severity_filter is not None:
        combo_map = {
            (path, sev): sources
            for (path, sev), sources in combo_map.items()
            if sev in severity_filter
        }

    # Count combinations that would be created
    combo_count = 0
    for (path, severity), sources in combo_map.items():
        if len(sources) < 2:
            continue
        combo_count += 1

        if args.dry_run:
            shortname = safe_shortname(path)
            outname = f"{shortname}-{severity}-combo.yaml" if severity else f"{shortname}-combo.yaml"
            print(f"[DRY-RUN] Would combine {len(sources)} files for {path} -> {outname}")
            for src, _ in sources:
                print(f"          - {src}")
        else:
            write_combo_yaml(path, severity, sources, out_dir, header_mode=args.header)

    if args.dry_run:
        print(f"\n[DRY-RUN] Would create {combo_count} combined file(s)")
        if not args.no_move:
            move_count = sum(1 for (_, _), sources in combo_map.items()
                             if len(sources) >= 2 for _ in sources)
            print(f"[DRY-RUN] Would move {move_count} original file(s) to combo/")
        print("[DRY-RUN] Run without --dry-run to apply changes")
    else:
        # Move originals that were combined to the combo/ subfolder (unless --no-move)
        if not args.no_move:
            move_originals_to_combo(combo_map, src_dir, combo_dir)
        else:
            print("Skipping move of originals (--no-move specified)")

        print(f"All combo files created in {out_dir}/.")


if __name__ == "__main__":
    main()
