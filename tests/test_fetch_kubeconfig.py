#!/usr/bin/env python3
"""Tests for lab-tools/fetch-kubeconfig.py."""
from __future__ import annotations

import importlib.util
import subprocess
import sys
import types
from pathlib import Path
from unittest.mock import Mock, call

import pytest


class _RequestException(Exception):
    pass


class _ConnectionError(_RequestException):
    pass


class _Timeout(_RequestException):
    pass


requests_stub = types.ModuleType('requests')
requests_stub.exceptions = types.SimpleNamespace(
    ConnectionError=_ConnectionError,
    Timeout=_Timeout,
    RequestException=_RequestException,
)
requests_stub.Session = Mock
bs4_stub = types.ModuleType('bs4')
bs4_stub.BeautifulSoup = Mock

script_path = Path(__file__).parent.parent / 'lab-tools' / 'fetch-kubeconfig.py'
spec = importlib.util.spec_from_file_location('fetch_kubeconfig', script_path)
fetch_kubeconfig = importlib.util.module_from_spec(spec)
with pytest.MonkeyPatch.context() as patch_modules:
    patch_modules.setitem(sys.modules, 'requests', requests_stub)
    patch_modules.setitem(sys.modules, 'bs4', bs4_stub)
    assert spec.loader is not None
    spec.loader.exec_module(fetch_kubeconfig)


class FakeCell:
    def __init__(self, text: str):
        self.text = text

    def get_text(self) -> str:
        return self.text


class FakeRow:
    def __init__(self, cells: list[str]):
        self.cells = [FakeCell(cell) for cell in cells]

    def find_all(self, _tags):
        return self.cells


class FakeTable:
    def __init__(self, rows: list[list[str]]):
        self.rows = [FakeRow(row) for row in rows]

    def find_all(self, _tag):
        return self.rows


class FakeSoup:
    def __init__(self, tables: list[FakeTable]):
        self.tables = tables

    def find_all(self, _tag):
        return self.tables


def test_check_node_status_parses_nodes_and_installer_ip(monkeypatch):
    session = Mock()
    session.get.return_value = types.SimpleNamespace(
        text='ignored', raise_for_status=Mock())
    monkeypatch.setattr(fetch_kubeconfig.requests, 'Session', lambda: session)
    monkeypatch.setattr(
        fetch_kubeconfig,
        'BeautifulSoup',
        lambda _text, _parser: FakeSoup([
            FakeTable([
                ['VM Name', 'Status', 'IP'],
                ['installer-1', 'Up', '10.0.0.10'],
                ['worker-1', 'Down', ''],
            ])
        ]),
    )

    result = fetch_kubeconfig.check_node_status(
        'https://example.test/status', verify_ssl=True)

    assert result == {
        'nodes': {
            'installer-1': {'status': 'up', 'ip': '10.0.0.10'},
            'worker-1': {'status': 'down', 'ip': None},
        },
        'installer_ip': '10.0.0.10',
    }
    session.get.assert_called_once_with(
        'https://example.test/status', timeout=10, verify=True)


def test_check_node_status_returns_empty_result_on_request_error(monkeypatch):
    session = Mock()
    session.get.side_effect = _Timeout('request timed out')
    monkeypatch.setattr(fetch_kubeconfig.requests, 'Session', lambda: session)

    result = fetch_kubeconfig.check_node_status('https://example.test/status')

    assert result == {'nodes': {}, 'installer_ip': None}


def test_remove_ssh_host_key_builds_command(monkeypatch):
    run = Mock(return_value=subprocess.CompletedProcess([], 0, '', ''))
    monkeypatch.setattr(fetch_kubeconfig.subprocess, 'run', run)

    assert fetch_kubeconfig.remove_ssh_host_key('10.0.0.10') is True
    run.assert_called_once_with(
        ['ssh-keygen', '-R', '10.0.0.10'],
        capture_output=True,
        text=True,
    )


def test_remove_ssh_host_key_returns_false_when_command_fails(monkeypatch):
    run = Mock(return_value=subprocess.CompletedProcess(
        [], 1, '', 'known_hosts error'))
    monkeypatch.setattr(fetch_kubeconfig.subprocess, 'run', run)

    assert fetch_kubeconfig.remove_ssh_host_key('10.0.0.10') is False


def test_fetch_kubeconfig_creates_destination_and_builds_scp_command(
        monkeypatch, tmp_path):
    destination = tmp_path / 'nested' / 'kubeconfig'
    which = subprocess.CompletedProcess([], 0, '', '')
    scp = subprocess.CompletedProcess([], 0, '', '')
    run = Mock(side_effect=[which, scp])
    chmod = Mock()
    monkeypatch.setattr(fetch_kubeconfig.subprocess, 'run', run)
    monkeypatch.setattr(fetch_kubeconfig.os, 'chmod', chmod)

    result = fetch_kubeconfig.fetch_kubeconfig(
        '10.0.0.10',
        remote_user='core',
        remote_path='/var/lib/kubeconfig',
        destination=str(destination),
    )

    assert result is True
    assert destination.parent.is_dir()
    assert run.call_args_list == [
        call(['which', 'scp'], capture_output=True, check=True),
        call(
            ['scp', '-o', 'StrictHostKeyChecking=no',
             '-o', 'UserKnownHostsFile=/dev/null',
             'core@10.0.0.10:/var/lib/kubeconfig', str(destination)],
            capture_output=True,
            text=True,
        ),
    ]
    chmod.assert_called_once_with(str(destination), 0o600)


def test_fetch_kubeconfig_returns_false_when_scp_is_unavailable(monkeypatch,
                                                                tmp_path):
    run = Mock(side_effect=subprocess.CalledProcessError(1, ['which', 'scp']))
    monkeypatch.setattr(fetch_kubeconfig.subprocess, 'run', run)

    result = fetch_kubeconfig.fetch_kubeconfig(
        '10.0.0.10', destination=str(tmp_path / 'kubeconfig'))

    assert result is False
    run.assert_called_once_with(['which', 'scp'], capture_output=True, check=True)


def test_main_uses_environment_to_select_url_and_destination(monkeypatch, tmp_path):
    monkeypatch.setattr(
        fetch_kubeconfig.sys,
        'argv',
        ['fetch-kubeconfig.py', '--env', 'cnfdc4'],
    )
    scrape = Mock(return_value='10.0.0.10')
    remove_key = Mock()
    fetch = Mock(return_value=True)
    monkeypatch.setattr(fetch_kubeconfig, 'scrape_installer_ip', scrape)
    monkeypatch.setattr(fetch_kubeconfig, 'remove_ssh_host_key', remove_key)
    monkeypatch.setattr(fetch_kubeconfig, 'fetch_kubeconfig', fetch)
    monkeypatch.setattr(fetch_kubeconfig.Path, 'home', lambda: tmp_path)

    with pytest.raises(SystemExit) as exc_info:
        fetch_kubeconfig.main()

    assert exc_info.value.code == 0
    scrape.assert_called_once_with(
        'https://succulent.eng.redhat.com/infoplan/cnfdc4',
        verify_ssl=False,
        wait_for_ready=False,
        max_wait_minutes=60,
        poll_interval=30,
    )
    remove_key.assert_called_once_with('10.0.0.10')
    fetch.assert_called_once_with(
        remote_ip='10.0.0.10',
        remote_user='root',
        remote_path='/root/ocp/auth/kubeconfig',
        destination=str(tmp_path / 'Downloads' / 'cnfdc4-kubeconfig'),
    )


def test_main_accepts_direct_ip_and_explicit_destination(monkeypatch, tmp_path):
    destination = tmp_path / 'custom-kubeconfig'
    monkeypatch.setattr(
        fetch_kubeconfig.sys,
        'argv',
        ['fetch-kubeconfig.py', '10.0.0.10', str(destination), '--user', 'core'],
    )
    remove_key = Mock()
    fetch = Mock(return_value=True)
    monkeypatch.setattr(fetch_kubeconfig, 'remove_ssh_host_key', remove_key)
    monkeypatch.setattr(fetch_kubeconfig, 'fetch_kubeconfig', fetch)

    with pytest.raises(SystemExit) as exc_info:
        fetch_kubeconfig.main()

    assert exc_info.value.code == 0
    remove_key.assert_called_once_with('10.0.0.10')
    fetch.assert_called_once_with(
        remote_ip='10.0.0.10',
        remote_user='core',
        remote_path='/root/ocp/auth/kubeconfig',
        destination=str(destination),
    )
