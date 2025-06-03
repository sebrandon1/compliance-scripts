#!/usr/bin/env python3
import os
import urllib.parse
import yaml
import argparse
from collections import defaultdict


def safe_shortname(path):
    """Convert a file path to a safe shortname for filenames."""
    return path.lstrip('/').replace('/', '_')


def parse_machineconfig_files(src_dir):
    """Parse all MachineConfig YAMLs in src_dir and group by file path."""
    combo_map = defaultdict(list)  # path -> list of
    # (source_file, decoded_lines)
    for fname in os.listdir(src_dir):
        # Skip non-YAMLs and the combo subdir
        if not fname.endswith('.yaml') or fname == 'combo':
            continue
        fpath = os.path.join(src_dir, fname)
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
                    lines = [line for line in decoded.splitlines()
                             if line.strip()]
                    combo_map[path].append((fname, lines))
    return combo_map


def write_combo_yaml(path, sources, out_dir):
    """Write a combined MachineConfig YAML for a
        given file path and list of sources."""
    all_lines = set()
    for _, lines in sources:
        all_lines.update(lines)
    deduped_lines = sorted(all_lines)
    shortname = safe_shortname(path)
    outname = f"rhcos4-{shortname}-combo.yaml"
    outpath = os.path.join(out_dir, outname)
    with open(outpath, "w") as out:
        out.write(
            "# Combined from the following remediations "
            f"for {path} (all roles):\n"
        )
        for src, _ in sources:
            out.write(f"#   - {src}\n")
        out.write(
            "apiVersion: machineconfiguration.openshift.io/v1\n"
            "kind: MachineConfig\n"
            "spec:\n"
            "  config:\n"
            "    ignition:\n"
            "      version: 3.1.0\n"
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
    for path, sources in combo_map.items():
        if len(sources) < 2:
            continue
        for src, _ in sources:
            if src not in moved:
                src_path = os.path.join(src_dir, src)
                if os.path.exists(src_path):
                    os.rename(src_path, os.path.join(combo_dir, src))
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
                    "deduplicating contents. Moves originals to a subfolder if "
                    "combined."
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
    args = parser.parse_args()

    src_dir = args.src_dir
    out_dir = args.out_dir
    combo_dir = os.path.join(src_dir, "combo")
    os.makedirs(combo_dir, exist_ok=True)
    os.makedirs(out_dir, exist_ok=True)

    # Parse and group MachineConfig YAMLs by file path
    combo_map = parse_machineconfig_files(src_dir)

    # Write combined YAMLs for each path with >1 source
    for path, sources in combo_map.items():
        if len(sources) < 2:
            continue  # Only combine if path appears more than once
        write_combo_yaml(path, sources, out_dir)

    # Move originals that were combined to the combo/ subfolder
    move_originals_to_combo(combo_map, src_dir, combo_dir)

    print(f"All combo files created in {out_dir}/.")


if __name__ == "__main__":
    main()
