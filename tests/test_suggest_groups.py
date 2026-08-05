#!/usr/bin/env python3
"""Tests for scripts/suggest-groups.py"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location(
    "suggest_groups",
    os.path.join(os.path.dirname(__file__), '..', 'scripts',
                 'suggest-groups.py'))
suggest_groups = module_from_spec(spec)
spec.loader.exec_module(suggest_groups)


class TestSuggestGroup:
    def test_sysctl_kernel_dmesg_matches_l2(self):
        gid, conf, _ = suggest_groups.suggest_group(
            "sysctl-kernel-dmesg-restrict", {}, {}
        )
        assert gid == "L2"
        assert conf == 0.95

    def test_sysctl_net_matches_m22(self):
        gid, conf, _ = suggest_groups.suggest_group(
            "sysctl-net-ipv4-something", {}, {}
        )
        assert gid == "M22"
        assert conf == 0.90

    def test_keyword_match_uses_medium_threshold(self):
        gid, conf, _ = suggest_groups.suggest_group(
            "test-check", {}, {"test": "M1"}
        )
        assert gid == "M1"
        assert conf == suggest_groups.MEDIUM_THRESHOLD

    def test_custom_medium_threshold_on_keyword(self):
        gid, conf, _ = suggest_groups.suggest_group(
            "test-check", {}, {"test": "M1"}, medium_threshold=0.3
        )
        assert conf == 0.3

    def test_no_match_returns_none(self):
        gid, conf, reason = suggest_groups.suggest_group(
            "completely-unknown-check", {}, {}
        )
        assert gid is None
        assert conf == 0.0
        assert reason == "no match"

    def test_prefix_match_below_threshold_falls_through(self):
        prefix_map = {"audit": {"M4": 1, "M5": 1}}
        gid, conf, _ = suggest_groups.suggest_group(
            "audit-rules-new", prefix_map, {}, medium_threshold=0.99
        )
        assert gid is None


class TestStripProfilePrefix:
    def test_rhcos4_e8_master(self):
        assert suggest_groups.strip_profile_prefix(
            "rhcos4-e8-master-sshd-disable-root-login"
        ) == "sshd-disable-root-login"

    def test_ocp4_cis(self):
        assert suggest_groups.strip_profile_prefix(
            "ocp4-cis-api-server-encryption"
        ) == "api-server-encryption"

    def test_no_prefix(self):
        assert suggest_groups.strip_profile_prefix(
            "configure-crypto-policy"
        ) == "configure-crypto-policy"

    def test_ocp4_moderate(self):
        assert suggest_groups.strip_profile_prefix(
            "ocp4-moderate-api-server-encryption"
        ) == "api-server-encryption"
