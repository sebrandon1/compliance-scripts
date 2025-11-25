#!/usr/bin/env python3
"""
Filter specific configuration flags from a combined MachineConfig YAML.

This script allows you to create focused MachineConfig files by selecting
only specific flags/directives from a combined configuration file.
"""

import os
import yaml
import urllib.parse
import argparse
from typing import List, Set


def parse_config_content(encoded_source: str) -> List[str]:
    """Parse the data:, encoded source and return list of config lines."""
    if not encoded_source.startswith('data:,'):
        raise ValueError("Source must start with 'data:,'")

    decoded = urllib.parse.unquote(encoded_source[6:])
    return [line.strip() for line in decoded.splitlines() if line.strip()]


def filter_config_lines(lines: List[str], flags: Set[str], case_sensitive: bool = False) -> List[str]:
    """
    Filter configuration lines to only include those matching the specified flags.

    Args:
        lines: List of configuration lines
        flags: Set of flag names to include (e.g., 'PermitRootLogin', 'PasswordAuthentication')
        case_sensitive: Whether to use case-sensitive matching

    Returns:
        List of filtered configuration lines
    """
    filtered = []

    for line in lines:
        # Skip comments and empty lines
        if line.startswith('#') or not line.strip():
            continue

        # Parse the flag name (first word)
        parts = line.split(None, 1)
        if not parts:
            continue

        flag_name = parts[0]

        # Check if this flag should be included
        if case_sensitive:
            if flag_name in flags:
                filtered.append(line)
        else:
            if flag_name.lower() in {f.lower() for f in flags}:
                filtered.append(line)

    return filtered


def create_filtered_machineconfig(
    input_file: str,
    output_file: str,
    flags: List[str],
    description: str = None,
    case_sensitive: bool = False
):
    """
    Create a filtered MachineConfig YAML with only specified flags.

    Args:
        input_file: Path to the combined MachineConfig YAML
        output_file: Path for the output filtered YAML
        flags: List of flag names to include
        description: Optional description for the header comment
        case_sensitive: Whether to use case-sensitive flag matching
    """
    # Read the input YAML
    with open(input_file, 'r') as f:
        doc = yaml.safe_load(f)

    if not doc or doc.get('kind') != 'MachineConfig':
        raise ValueError(f"{input_file} is not a valid MachineConfig")

    # Extract file configurations
    files = doc.get('spec', {}).get('config', {}).get('storage', {}).get('files', [])

    if not files:
        raise ValueError(f"No files found in {input_file}")

    # Process each file entry
    filtered_files = []
    for file_entry in files:
        path = file_entry.get('path')
        source = file_entry.get('contents', {}).get('source')
        mode = file_entry.get('mode', 384)
        overwrite = file_entry.get('overwrite', True)

        if not source or not source.startswith('data:,'):
            continue

        # Parse and filter the configuration lines
        all_lines = parse_config_content(source)
        filtered_lines = filter_config_lines(all_lines, set(flags), case_sensitive)

        if filtered_lines:
            filtered_files.append({
                'path': path,
                'lines': filtered_lines,
                'mode': mode,
                'overwrite': overwrite
            })

    if not filtered_files:
        print(f"Warning: No matching flags found in {input_file}")
        return

    # Write the output YAML
    with open(output_file, 'w') as out:
        # Write header comment if description provided
        if description:
            out.write(f"# {description}\n")

        out.write(f"# Filtered from: {os.path.basename(input_file)}\n")
        out.write(f"# Included flags: {', '.join(flags)}\n")
        out.write("\n")
        out.write("apiVersion: machineconfiguration.openshift.io/v1\n")
        out.write("kind: MachineConfig\n")
        out.write("spec:\n")
        out.write("  config:\n")
        out.write("    ignition:\n")
        out.write("      version: 3.5.0\n")
        out.write("    storage:\n")
        out.write("      files:\n")

        for file_info in filtered_files:
            out.write("        - contents:\n")
            out.write("            # Filtered configuration flags:\n")
            for line in file_info['lines']:
                out.write(f"            # {line}\n")

            # Encode the content
            content = "\n".join(file_info['lines']) + "\n"
            encoded = urllib.parse.quote(content, safe='')

            out.write("            source: data:,")
            out.write(encoded)
            out.write("\n")
            out.write(f"          mode: {file_info['mode']}\n")
            out.write(f"          overwrite: {str(file_info['overwrite']).lower()}\n")
            out.write(f"          path: {file_info['path']}\n")

    print(f"Created filtered MachineConfig: {output_file}")
    print(f"  Included {sum(len(f['lines']) for f in filtered_files)} configuration lines")


def main():
    parser = argparse.ArgumentParser(
        description="Filter specific flags from a combined MachineConfig YAML",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create a focused SSHD config with only top priority flags
  %(prog)s -i complianceremediations/sshd_config-high-combo.yaml \\
           -o complianceremediations/sshd_config-high-top5.yaml \\
           -f PermitRootLogin PasswordAuthentication PermitEmptyPasswords \\
              ClientAliveInterval ClientAliveCountMax PubkeyAuthentication \\
           -d "RAN Hardening (High): Top Priority SSHD Configuration"

  # Create a PAM config with specific password settings
  %(prog)s -i complianceremediations/password-auth-high-combo.yaml \\
           -o complianceremediations/password-auth-focused.yaml \\
           -f pam_pwquality.so pam_faillock.so \\
           -d "Focused password quality settings"

  # Use a flags file
  %(prog)s -i input.yaml -o output.yaml --flags-file my_flags.txt
"""
    )

    parser.add_argument(
        '-i', '--input',
        required=True,
        help='Input combined MachineConfig YAML file'
    )

    parser.add_argument(
        '-o', '--output',
        required=True,
        help='Output filtered MachineConfig YAML file'
    )

    parser.add_argument(
        '-f', '--flags',
        nargs='+',
        help='List of flag names to include (e.g., PermitRootLogin PasswordAuthentication)'
    )

    parser.add_argument(
        '--flags-file',
        help='File containing flag names (one per line)'
    )

    parser.add_argument(
        '-d', '--description',
        help='Description to add as a header comment'
    )

    parser.add_argument(
        '--case-sensitive',
        action='store_true',
        help='Use case-sensitive flag matching (default: case-insensitive)'
    )

    args = parser.parse_args()

    # Collect flags from arguments and/or file
    flags = []

    if args.flags:
        flags.extend(args.flags)

    if args.flags_file:
        with open(args.flags_file, 'r') as f:
            flags.extend([line.strip() for line in f if line.strip() and not line.startswith('#')])

    if not flags:
        parser.error("Must specify flags via -f/--flags or --flags-file")

    # Create the filtered config
    create_filtered_machineconfig(
        args.input,
        args.output,
        flags,
        args.description,
        args.case_sensitive
    )


if __name__ == "__main__":
    main()
