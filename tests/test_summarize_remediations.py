#!/usr/bin/env python3
"""Tests for core/summarize-remediations.py"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from unittest.mock import MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'core'))
from importlib.util import spec_from_file_location, module_from_spec

sys.modules.setdefault("anthropic", MagicMock())

spec = spec_from_file_location(
    "summarize_remediations",
    os.path.join(os.path.dirname(__file__), '..', 'core',
                 'summarize-remediations.py'))
summarize_remediations = module_from_spec(spec)
spec.loader.exec_module(summarize_remediations)

DESC = "A long enough description for summarization purposes here."


def _mock_client(response_text: str) -> MagicMock:
    client = MagicMock()
    content_block = MagicMock()
    content_block.text = response_text
    client.messages.create.return_value = MagicMock(content=[content_block])
    return client


class TestSummarizeRemediation:
    def test_empty_description_returns_empty(self):
        client = _mock_client("unused")
        result = summarize_remediations.summarize_remediation(client, "")
        assert result == ""
        client.messages.create.assert_not_called()

    def test_short_description_returns_empty(self):
        client = _mock_client("unused")
        result = summarize_remediations.summarize_remediation(
            client, "too short"
        )
        assert result == ""
        client.messages.create.assert_not_called()

    def test_valid_description_returns_summary(self):
        client = _mock_client("Set kernel.dmesg_restrict=1")
        result = summarize_remediations.summarize_remediation(client, DESC)
        assert result == "Set kernel.dmesg_restrict=1"

    def test_model_passed_to_api(self):
        client = _mock_client("summary text")
        summarize_remediations.summarize_remediation(
            client, DESC, model="claude-haiku-4-5-20251001"
        )
        call_kwargs = client.messages.create.call_args
        assert call_kwargs.kwargs["model"] == "claude-haiku-4-5-20251001"

    def test_default_model_used_when_not_specified(self):
        client = _mock_client("summary text")
        summarize_remediations.summarize_remediation(client, DESC)
        call_kwargs = client.messages.create.call_args
        assert call_kwargs.kwargs["model"] == summarize_remediations.DEFAULT_MODEL

    def test_long_summary_truncated(self):
        client = _mock_client("x" * 150)
        result = summarize_remediations.summarize_remediation(client, DESC)
        assert len(result) <= 100
        assert result.endswith("...")

    def test_quotes_stripped_from_summary(self):
        client = _mock_client('"Set X=Y"')
        result = summarize_remediations.summarize_remediation(client, DESC)
        assert not result.startswith('"')
        assert not result.endswith('"')

    def test_api_error_returns_empty(self):
        client = MagicMock()
        client.messages.create.side_effect = Exception("API error")
        result = summarize_remediations.summarize_remediation(client, DESC)
        assert result == ""


class TestCache:
    def test_cache_hit_skips_api(self):
        client = _mock_client("unused")
        key = summarize_remediations._cache_key(DESC)
        cache = {key: "cached summary"}
        result = summarize_remediations.summarize_remediation(
            client, DESC, cache=cache
        )
        assert result == "cached summary"
        client.messages.create.assert_not_called()

    def test_cache_miss_calls_api_and_stores(self):
        client = _mock_client("new summary")
        cache: dict[str, str] = {}
        result = summarize_remediations.summarize_remediation(
            client, DESC, cache=cache
        )
        assert result == "new summary"
        key = summarize_remediations._cache_key(DESC)
        assert cache[key] == "new summary"

    def test_offline_mode_returns_empty_on_miss(self):
        cache: dict[str, str] = {}
        result = summarize_remediations.summarize_remediation(
            None, DESC, cache=cache
        )
        assert result == ""

    def test_offline_mode_returns_cached(self):
        key = summarize_remediations._cache_key(DESC)
        cache = {key: "offline hit"}
        result = summarize_remediations.summarize_remediation(
            None, DESC, cache=cache
        )
        assert result == "offline hit"

    def test_cache_key_deterministic(self):
        k1 = summarize_remediations._cache_key(DESC)
        k2 = summarize_remediations._cache_key(DESC)
        assert k1 == k2

    def test_cache_key_differs_for_different_text(self):
        k1 = summarize_remediations._cache_key("description one is long enough")
        k2 = summarize_remediations._cache_key("description two is long enough")
        assert k1 != k2

    def test_load_cache_missing_file(self):
        cache = summarize_remediations.load_cache("/nonexistent/path.json")
        assert cache == {}

    def test_load_save_roundtrip(self):
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, "cache.json")
            data = {"abc123": "Set X=Y", "def456": "Configure Z"}
            summarize_remediations.save_cache(path, data)
            loaded = summarize_remediations.load_cache(path)
            assert loaded == data

    def test_load_cache_corrupt_json(self):
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, "cache.json")
            with open(path, 'w') as f:
                f.write("{invalid json")
            cache = summarize_remediations.load_cache(path)
            assert cache == {}

    def test_api_error_does_not_store_in_cache(self):
        client = MagicMock()
        client.messages.create.side_effect = Exception("API error")
        cache: dict[str, str] = {}
        result = summarize_remediations.summarize_remediation(
            client, DESC, cache=cache
        )
        assert result == ""
        assert len(cache) == 0


class TestProcessChecks:
    def test_adds_summary_to_check(self):
        client = _mock_client("Enable crypto policy")
        checks = [{"name": "configure-crypto-policy",
                   "description": "Long description text here for test."}]
        result = summarize_remediations.process_checks(client, checks)
        assert result[0]["summary"] == "Enable crypto policy"

    def test_skips_check_with_existing_summary(self):
        client = _mock_client("unused")
        checks = [{"name": "test", "description": "Long description text.",
                   "summary": "existing"}]
        result = summarize_remediations.process_checks(client, checks)
        assert result[0]["summary"] == "existing"
        client.messages.create.assert_not_called()

    def test_model_threaded_to_api(self):
        client = _mock_client("summary")
        checks = [{"name": "test",
                   "description": "Long description text here for test."}]
        summarize_remediations.process_checks(
            client, checks, model="custom-model"
        )
        call_kwargs = client.messages.create.call_args
        assert call_kwargs.kwargs["model"] == "custom-model"

    def test_process_checks_uses_cache(self):
        desc = "Long description text here for test."
        key = summarize_remediations._cache_key(desc)
        cache = {key: "from cache"}
        client = _mock_client("unused")
        checks = [{"name": "test", "description": desc}]
        result = summarize_remediations.process_checks(
            client, checks, cache=cache
        )
        assert result[0]["summary"] == "from cache"
        client.messages.create.assert_not_called()


class TestMainIntegration:
    def test_offline_with_cache(self):
        with tempfile.TemporaryDirectory() as td:
            desc = "Long description text here for test."
            key = summarize_remediations._cache_key(desc)
            cache_path = os.path.join(td, ".summary-cache.json")
            with open(cache_path, 'w') as f:
                json.dump({key: "cached value"}, f)

            json_path = os.path.join(td, "test.json")
            with open(json_path, 'w') as f:
                json.dump({
                    "version": "5.0",
                    "scan_date": "2026-01-01T00:00:00Z",
                    "summary": {"total_checks": 1, "passing": 0,
                                "failing": 1, "manual": 0},
                    "remediations": {
                        "high": [{"name": "test-check",
                                  "description": desc,
                                  "status": "FAIL",
                                  "severity": "high"}],
                        "medium": [], "low": []
                    }
                }, f)

            old_argv = sys.argv
            old_key = os.environ.get("ANTHROPIC_API_KEY")
            try:
                sys.argv = ["prog", json_path, "--offline",
                            "--cache-dir", td]
                if "ANTHROPIC_API_KEY" in os.environ:
                    del os.environ["ANTHROPIC_API_KEY"]
                summarize_remediations.main()
            finally:
                sys.argv = old_argv
                if old_key is not None:
                    os.environ["ANTHROPIC_API_KEY"] = old_key

            with open(json_path) as f:
                result = json.load(f)
            assert result["remediations"]["high"][0]["summary"] == "cached value"
