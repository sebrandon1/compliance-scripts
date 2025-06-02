#!/usr/bin/env python3
import os
import re
import urllib.parse
import yaml
import argparse
from collections import defaultdict

def safe_shortname(path):
    # Remove leading slashes and replace / with _
    return path.lstrip('/').replace('/', '_')

def main():
    parser = argparse.ArgumentParser(
        description="Combine OpenShift MachineConfig remediations by file path, deduplicating contents. Moves originals to a subfolder if combined."
    )
    parser.add_argument('--src-dir', default='complianceremediations', help='Source directory containing MachineConfig YAMLs (default: complianceremediations)')
    parser.add_argument('--out-dir', default='complianceremediations', help='Directory to write combined YAMLs (default: complianceremediations)')
    args = parser.parse_args()

    src_dir = args.src_dir
    out_dir = args.out_dir
    combo_dir = os.path.join(src_dir, "combo")
    os.makedirs(combo_dir, exist_ok=True)
    os.makedirs(out_dir, exist_ok=True)

    # path -> list of (source_file, decoded_lines)
    combo_map = defaultdict(list)

    for fname in os.listdir(src_dir):
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
            files = doc.get('spec', {}).get('config', {}).get('storage', {}).get('files', [])
            for file_entry in files:
                path = file_entry.get('path')
                source = file_entry.get('contents', {}).get('source')
                if path and source and source.startswith('data:,'):
                    decoded = urllib.parse.unquote(source[6:])
                    lines = [line for line in decoded.splitlines() if line.strip()]
                    combo_map[path].append((fname, lines))

    for path, sources in combo_map.items():
        if len(sources) < 2:
            continue  # Only combine if path appears more than once
        all_lines = set()
        for _, lines in sources:
            all_lines.update(lines)
        deduped_lines = sorted(all_lines)
        shortname = safe_shortname(path)
        outname = f"rhcos4-{shortname}-combo.yaml"
        outpath = os.path.join(out_dir, outname)
        with open(outpath, "w") as out:
            out.write(f"# Combined from the following remediations for {path} (all roles):\n")
            for src, _ in sources:
                out.write(f"#   - {src}\n")
            out.write(
                f"""apiVersion: machineconfiguration.openshift.io/v1\nkind: MachineConfig\nspec:\n  config:\n    ignition:\n      version: 3.1.0\n    storage:\n      files:\n        - contents:\n            # The following lines are the deduplicated, combined plaintext contents from all related MachineConfig remediations.\n""")
            for line in deduped_lines:
                out.write(f"            # {line}\n")
            out.write(f"            source: data:," )
            encoded = urllib.parse.quote("\n".join(deduped_lines) + "\n", safe='')
            out.write(encoded)
            out.write(f"""
          mode: 384
          overwrite: true
          path: {path}
""")
        print(f"Wrote {outpath}")

    # Move original files to combo folder (only once per file, and only if they were combined)
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

    print(f"Moved original remediations to {combo_dir}/ (only those used in combos)")
    print(f"All combo files created in {out_dir}/.")

if __name__ == "__main__":
    main()
