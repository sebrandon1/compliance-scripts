#!/usr/bin/env python3
"""Tests for scripts/add-version.py"""
from __future__ import annotations

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location(
    "add_version",
    os.path.join(os.path.dirname(__file__), '..', 'scripts',
                 'add-version.py'))
add_version = module_from_spec(spec)
spec.loader.exec_module(add_version)


def _setup_source_version(docs_dir: str, version: str = "5.0"):
    """Create minimal source version structure for testing."""
    slug = add_version.version_slug(version)

    os.makedirs(os.path.join(docs_dir, "versions", version, "groups"),
                exist_ok=True)
    os.makedirs(os.path.join(docs_dir, "_data"), exist_ok=True)

    with open(os.path.join(docs_dir, "versions", f"{version}.md"), 'w') as f:
        f.write(f'---\nlayout: version\ntitle: OCP {version} '
                f'Compliance Status\nversion: "{version}"\n---\n')

    with open(os.path.join(docs_dir, "versions", version,
                           "remediations.md"), 'w') as f:
        f.write(f'---\nlayout: remediations\ntitle: OCP {version} '
                f'Remediation Groupings\nversion: "{version}"\n---\n')

    with open(os.path.join(docs_dir, "versions", version,
                           "groups", "H1.md"), 'w') as f:
        f.write(f'---\nlayout: group\ngroup_id: H1\n'
                f'version: "{version}"\n---\n\n## Overview\n')

    with open(os.path.join(docs_dir, "versions", version,
                           "groups", "index.md"), 'w') as f:
        f.write(f'---\nlayout: default\ntitle: OCP {version} '
                f'Remediation Groups\nversion: "{version}"\n---\n\n'
                f'# OCP {version} Groups\n\n'
                f'[Back](../{version}.html)\n')

    tracking = {
        "meta": {"epic": "CNF-26078", "last_sync": "2026-01-01"},
        "groups": {
            "H1": {
                "title": "Crypto Policy",
                "severity": "HIGH",
                "priority": 1,
                "status": "verified",
                "platform": "rhcos",
                "status_note": "tested on cnfdt16",
                "jira": "CNF-12345",
                "jira_status": "Closed",
                "pr": "456",
                "pr_state": "merged",
                "last_sync": "2026-01-01",
                "compare": f"compliance/{version}/crypto-policy"
            }
        },
        "remediations": {
            "configure-crypto-policy": {"group": "H1"}
        }
    }
    with open(os.path.join(docs_dir, "_data",
                           f"tracking-{slug}.json"), 'w') as f:
        json.dump(tracking, f, indent=2)

    return docs_dir


class TestVersionSlug:
    def test_dots_replaced(self):
        assert add_version.version_slug("5.0") == "5_0"

    def test_major_minor(self):
        assert add_version.version_slug("4.22") == "4_22"


class TestReplaceVersion:
    def test_frontmatter_version(self):
        content = 'version: "5.0"'
        result = add_version._replace_version(content, "5.0", "5.1")
        assert 'version: "5.1"' in result

    def test_title(self):
        content = "OCP 5.0 Compliance Status"
        result = add_version._replace_version(content, "5.0", "5.1")
        assert "OCP 5.1 Compliance Status" in result

    def test_compare_links(self):
        content = "compliance/5.0/crypto-policy"
        result = add_version._replace_version(content, "5.0", "5.1")
        assert "compliance/5.1/crypto-policy" in result

    def test_data_file_slug(self):
        content = "ocp-5_0"
        result = add_version._replace_version(content, "5.0", "5.1")
        assert "ocp-5_1" in result

    def test_back_link(self):
        content = "../5.0.html"
        result = add_version._replace_version(content, "5.0", "5.1")
        assert "../5.1.html" in result


class TestCopyVersionPages:
    def test_creates_landing_page(self):
        with tempfile.TemporaryDirectory() as td:
            docs = os.path.join(td, "docs")
            _setup_source_version(docs, "5.0")

            add_version.copy_version_pages("5.0", "5.1", docs, False)

            dst = os.path.join(docs, "versions", "5.1.md")
            assert os.path.exists(dst)
            with open(dst) as f:
                content = f.read()
            assert 'version: "5.1"' in content
            assert "OCP 5.1" in content

    def test_copies_subdirectory(self):
        with tempfile.TemporaryDirectory() as td:
            docs = os.path.join(td, "docs")
            _setup_source_version(docs, "5.0")

            add_version.copy_version_pages("5.0", "5.1", docs, False)

            assert os.path.isdir(
                os.path.join(docs, "versions", "5.1", "groups"))
            h1 = os.path.join(docs, "versions", "5.1", "groups", "H1.md")
            assert os.path.exists(h1)
            with open(h1) as f:
                content = f.read()
            assert 'version: "5.1"' in content

    def test_skips_existing(self):
        with tempfile.TemporaryDirectory() as td:
            docs = os.path.join(td, "docs")
            _setup_source_version(docs, "5.0")
            _setup_source_version(docs, "5.1")

            created = add_version.copy_version_pages(
                "5.0", "5.1", docs, False
            )
            assert len(created) == 0

    def test_dry_run_creates_nothing(self):
        with tempfile.TemporaryDirectory() as td:
            docs = os.path.join(td, "docs")
            _setup_source_version(docs, "5.0")

            add_version.copy_version_pages("5.0", "5.1", docs, True)

            assert not os.path.exists(
                os.path.join(docs, "versions", "5.1.md"))


class TestCreateTracking:
    def test_creates_tracking_file(self):
        with tempfile.TemporaryDirectory() as td:
            docs = os.path.join(td, "docs")
            _setup_source_version(docs, "5.0")
            data_dir = os.path.join(docs, "_data")

            result = add_version.create_tracking(
                "5.0", "5.1", data_dir, False
            )

            assert result is not None
            assert os.path.exists(result)

            with open(result) as f:
                data = json.load(f)

            assert data["groups"]["H1"]["status"] == "pending"
            assert data["groups"]["H1"]["jira"] is None
            assert data["groups"]["H1"]["pr"] is None
            assert data["groups"]["H1"]["last_sync"] is None
            assert data["groups"]["H1"]["status_note"] is None

    def test_resets_meta(self):
        with tempfile.TemporaryDirectory() as td:
            docs = os.path.join(td, "docs")
            _setup_source_version(docs, "5.0")
            data_dir = os.path.join(docs, "_data")

            result = add_version.create_tracking(
                "5.0", "5.1", data_dir, False
            )

            with open(result) as f:
                data = json.load(f)

            assert data["meta"]["epic"] is None
            assert data["meta"]["last_sync"] is None

    def test_updates_compare_links(self):
        with tempfile.TemporaryDirectory() as td:
            docs = os.path.join(td, "docs")
            _setup_source_version(docs, "5.0")
            data_dir = os.path.join(docs, "_data")

            result = add_version.create_tracking(
                "5.0", "5.1", data_dir, False
            )

            with open(result) as f:
                data = json.load(f)

            assert "compliance/5.1/" in data["groups"]["H1"]["compare"]

    def test_preserves_remediations(self):
        with tempfile.TemporaryDirectory() as td:
            docs = os.path.join(td, "docs")
            _setup_source_version(docs, "5.0")
            data_dir = os.path.join(docs, "_data")

            result = add_version.create_tracking(
                "5.0", "5.1", data_dir, False
            )

            with open(result) as f:
                data = json.load(f)

            assert "configure-crypto-policy" in data["remediations"]
            assert data["remediations"]["configure-crypto-policy"]["group"] == "H1"

    def test_skips_existing(self):
        with tempfile.TemporaryDirectory() as td:
            docs = os.path.join(td, "docs")
            _setup_source_version(docs, "5.0")
            _setup_source_version(docs, "5.1")
            data_dir = os.path.join(docs, "_data")

            result = add_version.create_tracking(
                "5.0", "5.1", data_dir, False
            )
            assert result is None

    def test_dry_run_creates_nothing(self):
        with tempfile.TemporaryDirectory() as td:
            docs = os.path.join(td, "docs")
            _setup_source_version(docs, "5.0")
            data_dir = os.path.join(docs, "_data")

            add_version.create_tracking("5.0", "5.1", data_dir, True)

            assert not os.path.exists(
                os.path.join(data_dir, "tracking-5_1.json"))

    def test_falls_back_to_shared_tracking(self):
        with tempfile.TemporaryDirectory() as td:
            docs = os.path.join(td, "docs")
            os.makedirs(os.path.join(docs, "_data"), exist_ok=True)
            os.makedirs(os.path.join(docs, "versions", "5.0", "groups"),
                        exist_ok=True)

            tracking = {
                "meta": {"epic": None},
                "groups": {
                    "H1": {
                        "title": "Test",
                        "severity": "HIGH",
                        "priority": 1,
                        "status": "verified",
                        "platform": "rhcos",
                    }
                },
                "remediations": {}
            }
            with open(os.path.join(docs, "_data", "tracking.json"), 'w') as f:
                json.dump(tracking, f)

            result = add_version.create_tracking(
                "5.0", "5.1", os.path.join(docs, "_data"), False
            )
            assert result is not None
            assert os.path.exists(result)
