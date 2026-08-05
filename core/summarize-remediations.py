#!/usr/bin/env python3
"""
Summarize compliance remediation descriptions using Claude API.
Adds a concise "summary" field to each check in the JSON data file.

Supports offline/cached mode: previously generated summaries are cached
to disk and served when the API key is missing or rate-limited.

Requires: ANTHROPIC_API_KEY environment variable (optional with --offline)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
from typing import Any


DEFAULT_MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-20250514")
CACHE_FILENAME = ".summary-cache.json"


def _cache_key(description: str) -> str:
    """Hash a description to produce a stable cache key."""
    normalized = description[:2000].strip()
    return hashlib.sha256(normalized.encode()).hexdigest()


def load_cache(cache_path: str) -> dict[str, str]:
    """Load the summary cache from disk."""
    if os.path.exists(cache_path):
        try:
            with open(cache_path) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def save_cache(cache_path: str, cache: dict[str, str]) -> None:
    """Atomically write the summary cache to disk."""
    tmp_fd, tmp_path = tempfile.mkstemp(
        suffix='.json', dir=os.path.dirname(os.path.abspath(cache_path))
    )
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            json.dump(cache, f, indent=2)
        os.replace(tmp_path, cache_path)
    except BaseException:
        os.unlink(tmp_path)
        raise


def summarize_remediation(
    client: Any | None, description: str,
    cache: dict[str, str] | None = None,
    model: str = DEFAULT_MODEL,
) -> str:
    """Use Claude to generate a one-line remediation summary.

    Checks the cache first. Falls back to cache-only if client is None.
    """
    if not description or len(description.strip()) < 10:
        return ""

    key = _cache_key(description)

    if cache is not None and key in cache:
        return cache[key]

    if client is None:
        return ""

    try:
        response = client.messages.create(
            model=model,
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
        summary = summary.strip('"\'')
        if len(summary) > 100:
            summary = summary[:97] + "..."

        if cache is not None:
            cache[key] = summary

        return summary
    except Exception as e:
        print(f"  Warning: Failed to summarize: {e}", file=sys.stderr)
        return ""


def process_checks(
    client: Any | None, checks: list[dict[str, Any]],
    cache: dict[str, str] | None = None,
    model: str = DEFAULT_MODEL,
) -> list[dict[str, Any]]:
    """Add summaries to a list of checks."""
    for check in checks:
        name = check.get("name", "unknown")
        description = check.get("description", "")

        if description and not check.get("summary"):
            print(f"  Summarizing: {name}")
            summary = summarize_remediation(client, description, cache, model)
            if summary:
                check["summary"] = summary
                print(f"    -> {summary}")
            else:
                print("    -> (no summary available)")
        elif check.get("summary"):
            print(f"  Already has summary: {name}")

    return checks


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate AI summaries for compliance remediations"
    )
    parser.add_argument(
        "json_file",
        help="Path to the compliance JSON file"
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help="Anthropic model name (env: ANTHROPIC_MODEL, default: %(default)s)"
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Offline mode: use cached summaries only, skip API calls"
    )
    parser.add_argument(
        "--cache-dir",
        metavar="DIR",
        help="Directory for the summary cache file (default: same as json_file)"
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Disable caching entirely"
    )
    args = parser.parse_args()

    json_file = args.json_file

    if not os.path.exists(json_file):
        print(f"Error: File not found: {json_file}", file=sys.stderr)
        sys.exit(1)

    cache_dir = args.cache_dir or os.path.dirname(os.path.abspath(json_file))
    cache_path = os.path.join(cache_dir, CACHE_FILENAME)
    cache: dict[str, str] | None = None
    if not args.no_cache:
        cache = load_cache(cache_path)
        print(f"Loaded {len(cache)} cached summaries from {cache_path}")

    client = None
    api_key = os.environ.get("ANTHROPIC_API_KEY")

    if args.offline:
        print("Running in offline mode (cached summaries only)")
    elif not api_key:
        if cache:
            print(
                "Warning: ANTHROPIC_API_KEY not set, "
                "falling back to cached summaries",
                file=sys.stderr
            )
        else:
            print(
                "Error: ANTHROPIC_API_KEY not set and no cache available",
                file=sys.stderr
            )
            sys.exit(1)
    else:
        import anthropic
        client = anthropic.Anthropic(api_key=api_key)
        print(f"Using model: {args.model}")

    print(f"Loading {json_file}...")
    with open(json_file, 'r') as f:
        data = json.load(f)

    print("\nProcessing HIGH severity checks...")
    if data.get("remediations", {}).get("high"):
        data["remediations"]["high"] = process_checks(
            client, data["remediations"]["high"], cache, args.model
        )

    print("\nProcessing MEDIUM severity checks...")
    if data.get("remediations", {}).get("medium"):
        data["remediations"]["medium"] = process_checks(
            client, data["remediations"]["medium"], cache, args.model
        )

    print("\nProcessing LOW severity checks...")
    if data.get("remediations", {}).get("low"):
        data["remediations"]["low"] = process_checks(
            client, data["remediations"]["low"], cache, args.model
        )

    print("\nProcessing MANUAL checks...")
    if data.get("manual_checks"):
        data["manual_checks"] = process_checks(
            client, data["manual_checks"], cache, args.model
        )

    if cache is not None and not args.no_cache:
        save_cache(cache_path, cache)
        print(f"Saved {len(cache)} summaries to cache")

    print(f"\nWriting updated data to {json_file}...")
    tmp_fd, tmp_path = tempfile.mkstemp(
        suffix='.json', dir=os.path.dirname(os.path.abspath(json_file))
    )
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            json.dump(data, f, indent=2)
        os.replace(tmp_path, json_file)
    except BaseException:
        os.unlink(tmp_path)
        raise

    print("Done!")


if __name__ == "__main__":
    main()
