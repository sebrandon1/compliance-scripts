#!/usr/bin/env python3
import os
import re
import urllib.parse
import yaml
from collections import defaultdict

def safe_shortname(path):
    # Remove leading slashes and replace / with _
    return path.lstrip('/').replace('/', '_')

src_dir = "complianceremediations"
combo_dir = os.path.join(src_dir, "combo")
os.makedirs(combo_dir, exist_ok=True)

# path -> list of (source_file, decoded_lines)
combo_map = defaultdict(list)

for fname in os.listdir(src_dir):
    if not fname.endswith('.yaml') or fname == 'sshd_combined.yaml':
        continue
    with open(os.path.join(src_dir, fname)) as f:
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
    outpath = os.path.join(src_dir, outname)  # Save in complianceremediations/
    with open(outpath, "w") as out:
        out.write(f"# Combined from the following remediations for {path} (all roles):\n")
        for src, _ in sources:
            out.write(f"#   - {src}\n")
        out.write(
            f"""apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
spec:
  config:
    ignition:
      version: 3.1.0
    storage:
      files:
        - contents:
            # The following lines are the deduplicated, combined plaintext contents from all related MachineConfig remediations.\n""")
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
            os.rename(os.path.join(src_dir, src), os.path.join(combo_dir, src))
            moved.add(src)

print(f"Moved original remediations to {combo_dir}/ (only those used in combos)")
print("All combo files created in complianceremediations/.")
