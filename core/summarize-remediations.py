#!/usr/bin/env python3
"""
Summarize compliance remediation descriptions using Claude API.
Adds a concise "summary" field to each check in the JSON data file.

Usage: ./summarize-remediations.py <json-file>
Example: ./summarize-remediations.py docs/_data/ocp-4_21.json

Requires: ANTHROPIC_API_KEY environment variable
"""

import json
import os
import sys
import anthropic


def summarize_remediation(client, description: str) -> str:
    """Use Claude to generate a one-line remediation summary."""
    if not description or len(description.strip()) < 10:
        return ""

    try:
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=150,
            messages=[
                {
                    "role": "user",
                    "content": f"""Summarize this OpenShift compliance remediation in ONE short line (max 80 chars).
Focus on the specific action needed: the flag to set, file to modify, or setting to change.
Use imperative form like "Set X=Y" or "Configure X in Y".
Do NOT include explanations or context.

Remediation:
{description[:2000]}

One-line summary:"""
                }
            ]
        )
        summary = response.content[0].text.strip()
        # Clean up any quotes or extra formatting
        summary = summary.strip('"\'')
        # Truncate if too long
        if len(summary) > 100:
            summary = summary[:97] + "..."
        return summary
    except Exception as e:
        print(f"  Warning: Failed to summarize: {e}", file=sys.stderr)
        return ""


def process_checks(client, checks: list) -> list:
    """Add summaries to a list of checks."""
    for i, check in enumerate(checks):
        name = check.get("name", "unknown")
        description = check.get("description", "")

        if description and not check.get("summary"):
            print(f"  Summarizing: {name}")
            summary = summarize_remediation(client, description)
            check["summary"] = summary
            print(f"    -> {summary}")
        elif check.get("summary"):
            print(f"  Already has summary: {name}")

    return checks


def main():
    if len(sys.argv) < 2:
        print("Usage: ./summarize-remediations.py <json-file>", file=sys.stderr)
        sys.exit(1)

    json_file = sys.argv[1]

    if not os.path.exists(json_file):
        print(f"Error: File not found: {json_file}", file=sys.stderr)
        sys.exit(1)

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("Error: ANTHROPIC_API_KEY environment variable not set", file=sys.stderr)
        sys.exit(1)

    print(f"Loading {json_file}...")
    with open(json_file, 'r') as f:
        data = json.load(f)

    client = anthropic.Anthropic(api_key=api_key)

    # Process each severity level
    print("\nProcessing HIGH severity checks...")
    if data.get("remediations", {}).get("high"):
        data["remediations"]["high"] = process_checks(client, data["remediations"]["high"])

    print("\nProcessing MEDIUM severity checks...")
    if data.get("remediations", {}).get("medium"):
        data["remediations"]["medium"] = process_checks(client, data["remediations"]["medium"])

    print("\nProcessing LOW severity checks...")
    if data.get("remediations", {}).get("low"):
        data["remediations"]["low"] = process_checks(client, data["remediations"]["low"])

    print("\nProcessing MANUAL checks...")
    if data.get("manual_checks"):
        data["manual_checks"] = process_checks(client, data["manual_checks"])

    # Write back
    print(f"\nWriting updated data to {json_file}...")
    with open(json_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("Done!")


if __name__ == "__main__":
    main()
