#!/usr/bin/env python3
import os
import urllib.parse


def process_file(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()
    # Quick check for kind: MachineConfig
    if not any('kind: MachineConfig' in line for line in lines):
        return False
    new_lines = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # Look for indented source: data:,<encoded>
        if 'source: data:,' in line:
            indent = line[:line.index('source:')]
            encoded = line.split('source: data:,', 1)[1].strip()
            decoded = urllib.parse.unquote(encoded)
            decoded_lines = [
                f"{indent}# {decoded_line}\n"
                for decoded_line in decoded.rstrip('\n').split('\n')
            ]
            # Remove any # encoded_data lines immediately above
            while new_lines and new_lines[-1].lstrip().startswith('# encoded_data'):
                new_lines.pop()
            # Check if the decoded comment block already exists immediately above
            already_present = True
            for j in range(1, len(decoded_lines) + 1):
                if (len(new_lines) < j or new_lines[-j] != decoded_lines[-j]):
                    already_present = False
                    break
            if not already_present:
                new_lines.extend(decoded_lines)
        new_lines.append(line)
        i += 1
    with open(filepath, 'w') as f:
        f.writelines(new_lines)
    return True


def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    cr_dir = os.path.join(base_dir, 'complianceremediations')
    for fname in os.listdir(cr_dir):
        if not fname.endswith('.yaml'):
            continue
        fpath = os.path.join(cr_dir, fname)
        if process_file(fpath):
            print(f"Processed: {fname}")
        else:
            print(f"Skipped: {fname}")


if __name__ == '__main__':
    main()
