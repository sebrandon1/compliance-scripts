#!/usr/bin/env python3
"""Tests for lab-tools/reprovision-cluster.py."""
from __future__ import annotations

import importlib.util
import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, Mock

import pytest


class FakePlaywrightTimeoutError(Exception):
    pass


playwright_stub = types.ModuleType('playwright')
sync_api_stub = types.ModuleType('playwright.sync_api')
sync_api_stub.sync_playwright = Mock()
sync_api_stub.TimeoutError = FakePlaywrightTimeoutError
playwright_stub.sync_api = sync_api_stub

script_path = Path(__file__).parent.parent / 'lab-tools' / 'reprovision-cluster.py'
spec = importlib.util.spec_from_file_location('reprovision_cluster', script_path)
reprovision_cluster = importlib.util.module_from_spec(spec)
with pytest.MonkeyPatch.context() as patch_modules:
    patch_modules.setitem(sys.modules, 'playwright', playwright_stub)
    patch_modules.setitem(sys.modules, 'playwright.sync_api', sync_api_stub)
    assert spec.loader is not None
    spec.loader.exec_module(reprovision_cluster)


class BrowserStack:
    def __init__(self):
        self.page = Mock()
        self.locator = Mock()
        self.locator.first = self.locator
        self.locator.is_visible.return_value = True
        self.page.locator.return_value = self.locator
        self.page.context = Mock()
        self.context = self.page.context
        self.context.new_page.return_value = self.page
        self.browser = Mock()
        self.browser.new_context.return_value = self.context
        self.playwright = Mock()
        self.playwright.chromium.launch.return_value = self.browser
        self.manager = MagicMock()
        self.manager.__enter__.return_value = self.playwright


def test_reprovision_cluster_fills_form_and_submits(monkeypatch, tmp_path):
    stack = BrowserStack()
    monkeypatch.setattr(
        reprovision_cluster,
        'sync_playwright',
        lambda: stack.manager,
    )
    monkeypatch.setattr(reprovision_cluster.time, 'sleep', lambda _seconds: None)
    monkeypatch.setattr(reprovision_cluster.Path, 'home', lambda: tmp_path)

    result = reprovision_cluster.reprovision_cluster(
        ocp_version='4.18',
        email='user@example.com',
        kerberos_id='user',
        url='https://example.test/exposeform/cnfdc3',
        retries=1,
    )

    assert result is True
    stack.playwright.chromium.launch.assert_called_once_with(
        headless=True,
        args=['--ignore-certificate-errors', '--disable-web-security'],
    )
    stack.page.goto.assert_called_once_with(
        'https://example.test/exposeform/cnfdc3',
        wait_until='networkidle',
        timeout=30000,
    )
    assert stack.locator.fill.call_count >= 2
    stack.locator.clear.assert_called_once()
    stack.locator.select_option.assert_called_once_with(label='nightly')
    stack.locator.click.assert_called_once_with(no_wait_after=True)
    assert stack.page.screenshot.call_count == 2
    stack.browser.close.assert_called_once()


def test_reprovision_cluster_dry_run_is_visible_and_does_not_submit(
        monkeypatch, tmp_path):
    stack = BrowserStack()
    monkeypatch.setattr(reprovision_cluster, 'sync_playwright',
                        lambda: stack.manager)
    monkeypatch.setattr(reprovision_cluster.time, 'sleep', lambda _seconds: None)
    monkeypatch.setattr(reprovision_cluster.Path, 'home', lambda: tmp_path)

    result = reprovision_cluster.reprovision_cluster(
        ocp_version='4.17',
        email='user@example.com',
        kerberos_id='user',
        headless=False,
        dry_run=True,
        url='https://example.test/exposeform/cnfdc3',
        retries=1,
    )

    assert result is True
    stack.playwright.chromium.launch.assert_called_once_with(
        headless=False,
        args=['--ignore-certificate-errors', '--disable-web-security'],
    )
    stack.locator.click.assert_not_called()
    stack.page.screenshot.assert_called_once()


def test_reprovision_cluster_retries_after_timeout(monkeypatch, tmp_path):
    stack = BrowserStack()
    failing_manager = MagicMock()
    failing_manager.__enter__.side_effect = (
        reprovision_cluster.PlaywrightTimeoutError('timed out'),
    )
    monkeypatch.setattr(
        reprovision_cluster,
        'sync_playwright',
        Mock(side_effect=[failing_manager, stack.manager]),
    )
    sleeps = []
    monkeypatch.setattr(reprovision_cluster.time, 'sleep', sleeps.append)
    monkeypatch.setattr(reprovision_cluster.Path, 'home', lambda: tmp_path)

    result = reprovision_cluster.reprovision_cluster(
        ocp_version='4.18',
        email='user@example.com',
        kerberos_id='user',
        url='https://example.test/exposeform/cnfdc3',
        retries=2,
    )

    assert result is True
    assert sleeps[0] == 4
    stack.playwright.chromium.launch.assert_called_once()


@pytest.mark.parametrize(
    'argv',
    [
        ['reprovision-cluster.py', '--email', 'user@example.com',
         '--kerberos-id', 'user', '--env', 'cnfdc3'],
        ['reprovision-cluster.py', '4.18', '--email', 'user@example.com',
         '--kerberos-id', 'user'],
    ],
)
def test_main_validates_required_version_and_environment(monkeypatch, argv):
    monkeypatch.setattr(reprovision_cluster.sys, 'argv', argv)

    with pytest.raises(SystemExit) as exc_info:
        reprovision_cluster.main()

    assert exc_info.value.code == 1
