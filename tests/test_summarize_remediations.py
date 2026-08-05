#!/usr/bin/env python3
"""Tests for core/summarize-remediations.py"""
from __future__ import annotations

import os
import sys
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
        result = summarize_remediations.summarize_remediation(client, "too short")
        assert result == ""
        client.messages.create.assert_not_called()

    def test_valid_description_returns_summary(self):
        client = _mock_client("Set kernel.dmesg_restrict=1")
        result = summarize_remediations.summarize_remediation(
            client, "A long enough description for summarization purposes here."
        )
        assert result == "Set kernel.dmesg_restrict=1"

    def test_model_passed_to_api(self):
        client = _mock_client("summary text")
        summarize_remediations.summarize_remediation(
            client, "A long enough description for summarization purposes here.",
            model="claude-haiku-4-5-20251001"
        )
        call_kwargs = client.messages.create.call_args
        assert call_kwargs.kwargs["model"] == "claude-haiku-4-5-20251001"

    def test_default_model_used_when_not_specified(self):
        client = _mock_client("summary text")
        summarize_remediations.summarize_remediation(
            client, "A long enough description for summarization purposes here."
        )
        call_kwargs = client.messages.create.call_args
        assert call_kwargs.kwargs["model"] == summarize_remediations.DEFAULT_MODEL

    def test_long_summary_truncated(self):
        client = _mock_client("x" * 150)
        result = summarize_remediations.summarize_remediation(
            client, "A long enough description for summarization purposes here."
        )
        assert len(result) <= 100
        assert result.endswith("...")

    def test_quotes_stripped_from_summary(self):
        client = _mock_client('"Set X=Y"')
        result = summarize_remediations.summarize_remediation(
            client, "A long enough description for summarization purposes here."
        )
        assert not result.startswith('"')
        assert not result.endswith('"')

    def test_api_error_returns_empty(self):
        client = MagicMock()
        client.messages.create.side_effect = Exception("API error")
        result = summarize_remediations.summarize_remediation(
            client, "A long enough description for summarization purposes here."
        )
        assert result == ""


class TestProcessChecks:
    def test_adds_summary_to_check(self):
        client = _mock_client("Enable crypto policy")
        checks = [{"name": "configure-crypto-policy", "description": "Long description text here for test."}]
        result = summarize_remediations.process_checks(client, checks)
        assert result[0]["summary"] == "Enable crypto policy"

    def test_skips_check_with_existing_summary(self):
        client = _mock_client("unused")
        checks = [{"name": "test", "description": "Long description text.", "summary": "existing"}]
        result = summarize_remediations.process_checks(client, checks)
        assert result[0]["summary"] == "existing"
        client.messages.create.assert_not_called()

    def test_model_threaded_to_api(self):
        client = _mock_client("summary")
        checks = [{"name": "test", "description": "Long description text here for test."}]
        summarize_remediations.process_checks(client, checks, model="custom-model")
        call_kwargs = client.messages.create.call_args
        assert call_kwargs.kwargs["model"] == "custom-model"
