#!/usr/bin/env python3
"""Static checks that image-mirror workflows use IMAGE_REGISTRY, not a hardcoded quay namespace."""
from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
WORKFLOWS = (
    "mirror-compliance-images.yml",
    "build-k8scontent.yml",
    "verify-mirror-architectures.yml",
)
DEFAULT_REGISTRY = "${{ vars.IMAGE_REGISTRY || 'quay.io/bapalm' }}"
DEFAULT_HOST = "${{ vars.IMAGE_HOST || 'quay.io' }}"


def _workflow(name: str) -> str:
    return (REPO / ".github" / "workflows" / name).read_text()


def test_workflows_set_image_registry_from_repo_variable():
    for name in WORKFLOWS:
        text = _workflow(name)
        assert DEFAULT_REGISTRY in text, f"{name} must default IMAGE_REGISTRY from vars"


def test_push_workflows_login_to_image_host():
    for name in ("mirror-compliance-images.yml", "build-k8scontent.yml"):
        text = _workflow(name)
        assert DEFAULT_HOST in text, f"{name} must default IMAGE_HOST from vars"
        assert "registry: ${{ env.IMAGE_HOST }}" in text
        assert "registry: quay.io" not in text
        assert "skopeo login quay.io" not in text


def test_workflows_do_not_hardcode_quay_namespace():
    for name in WORKFLOWS:
        leftover = _workflow(name).replace(DEFAULT_REGISTRY, "")
        leftover = leftover.replace(DEFAULT_HOST, "")
        assert "quay.io/bapalm" not in leftover, f"{name} still hardcodes quay.io/bapalm"


def test_mirror_action_tags_use_env_image_registry():
    text = _workflow("mirror-compliance-images.yml")
    tags = re.findall(r"^\s+tags: .+$", text, re.MULTILINE)
    assert tags, "expected docker/build-push-action tags"
    for line in tags:
        assert "${{ env.IMAGE_REGISTRY }}" in line, line
