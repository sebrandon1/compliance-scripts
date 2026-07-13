#!/usr/bin/env python3
"""
Combine MachineConfig remediations by file path.

Multiple compliance remediations often target the same file path (e.g., several
rules writing to /etc/sysctl.d/99-compliance.conf). Applying them individually
would cause conflicts because only the last MachineConfig wins per file path.
This script merges all remediations that target the same file path into a single
combined MachineConfig with deduplicated contents.

For an alternative approach that uses .d directory includes (one file per rule),
see modular/create-modular-configs.sh and model-context/MODULAR_APPROACH.md.

Usage:
    python3 core/combine-machineconfigs-by-path.py \\
        --src-dir complianceremediations --out-dir complianceremediations \\
        [--severity high,medium,low] [--header none|provenance|full] \\
        [--no-move] [--dry-run]
"""
import os
import sys
import urllib.parse
import argparse

# Add project root to path for shared module imports
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from lib.compliance_utils import (  # noqa: E402
    safe_shortname, parse_machineconfig_files as _parse_mc_files,
    parse_severity_filter,
)


def parse_machineconfig_files(src_dir):
    """Parse MachineConfig YAMLs, skipping the combo/ subdirectory."""
    return _parse_mc_files(src_dir, exclude_dirs={'combo'})


def write_combo_yaml(path, severity, sources, out_dir, header_mode="none"):
    """Write a combined MachineConfig YAML for a given file path and severity.
    Sources is a list of dicts with 'source_file' and 'lines' keys.
    """
    all_lines = set()
    for source in sources:
        all_lines.update(source['lines'])
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
                for source in sources:
                    out.write(f"#   - {source['source_file']}\n")
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
        for source in sources:
            src = source['source_file']
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
    severity_filter = parse_severity_filter(args.severity)
    combo_dir = os.path.join(src_dir, "combo")

    if args.dry_run:
        print("[DRY-RUN] Preview mode - no files will be modified")
    else:
        os.makedirs(combo_dir, exist_ok=True)
        os.makedirs(out_dir, exist_ok=True)

    # Parse and group MachineConfig YAMLs by (file path, severity)
    combo_map, skipped = parse_machineconfig_files(src_dir)
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
            for source in sources:
                print(f"          - {source['source_file']}")
        else:
            write_combo_yaml(path, severity, sources, out_dir, header_mode=args.header)

    if args.dry_run:
        print(f"\n[DRY-RUN] Would create {combo_count} combined file(s)")
        if not args.no_move:
            move_count = sum(1 for (_, _), sources in combo_map.items()
                             if len(sources) >= 2 for _s in sources)
            print(f"[DRY-RUN] Would move {move_count} original file(s) to combo/")
        print("[DRY-RUN] Run without --dry-run to apply changes")
    else:
        # Move originals that were combined to the combo/ subfolder (unless --no-move)
        if not args.no_move:
            move_originals_to_combo(combo_map, src_dir, combo_dir)
        else:
            print("Skipping move of originals (--no-move specified)")

        print(f"All combo files created in {out_dir}/.")

    if skipped:
        print(f"\nWARNING: {len(skipped)} file(s) skipped due to YAML parse errors:",
              file=sys.stderr)
        for fpath, err in skipped:
            print(f"  - {fpath}: {err}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
