#!/usr/bin/env python3
"""Static checks for the mobile hamburger navigation."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT = (REPO / "docs" / "_layouts" / "default.html").read_text()
CSS = (REPO / "docs" / "assets" / "css" / "style.css").read_text()


def test_nav_toggle_button_markup():
    assert 'id="nav-toggle"' in DEFAULT
    assert 'aria-controls="nav-links"' in DEFAULT
    assert 'aria-expanded="false"' in DEFAULT
    assert 'aria-label="Menu"' in DEFAULT
    assert 'id="nav-links"' in DEFAULT


def test_nav_toggle_js_closes_on_escape_and_link_click():
    assert "function setNavOpen(open)" in DEFAULT
    assert "setNavOpen(false)" in DEFAULT
    assert "initNavToggle" in DEFAULT


def test_css_hides_toggle_on_desktop_and_shows_at_768():
    desktop = CSS[:CSS.index("@media (max-width: 768px)")]
    mobile = CSS[CSS.index("@media (max-width: 768px)"):]
    assert ".nav-toggle {\n  display: none;" in desktop
    assert ".nav-toggle {\n    display: inline-flex;" in mobile
    assert ".nav-links.open" in mobile
    assert "display: flex;" in mobile[mobile.index(".nav-links.open"):]
