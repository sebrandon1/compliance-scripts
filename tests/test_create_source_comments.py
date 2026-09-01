import sys
import os
import urllib.parse

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'misc')))

create_source_comments = __import__('create-source-comments')
process_file = create_source_comments.process_file


def _make_mc_file(tmp_path, name: str, raw_data: str, extra_line: str = "") -> tuple:
    encoded = urllib.parse.quote(raw_data)
    content = (
        "kind: MachineConfig\n"
        "spec:\n"
        "  config:\n"
        "    storage:\n"
        "      files:\n"
        "      - path: /etc/motd\n"
        + (f"        {extra_line}\n" if extra_line else "")
        + f"        source: data:,{encoded}\n"
    )
    p = tmp_path / name
    p.write_text(content)
    return p, content, encoded


def test_process_file_non_machine_config(tmp_path):
    p = tmp_path / "not_mc.yaml"
    content = "kind: ConfigMap\nmetadata:\n  name: test\n"
    p.write_text(content)

    assert process_file(str(p)) is False
    assert p.read_text() == content


def test_process_file_insertion(tmp_path):
    p, _, encoded = _make_mc_file(tmp_path, "mc.yaml", "Hello\nWorld")

    assert process_file(str(p)) is True
    updated = p.read_text()
    assert "        # Hello\n" in updated
    assert "        # World\n" in updated
    assert "        # World\n        source: data:," in updated


def test_process_file_idempotent(tmp_path):
    p, content, _ = _make_mc_file(
        tmp_path, "mc_idempotent.yaml", "Already here", extra_line="# Already here"
    )

    assert process_file(str(p)) is True
    assert p.read_text() == content


def test_process_file_removes_encoded_data_comment(tmp_path):
    p, _, _ = _make_mc_file(
        tmp_path, "mc_cleanup.yaml", "Clean me", extra_line="# encoded_data: old stuff"
    )

    assert process_file(str(p)) is True
    updated = p.read_text()
    assert "# encoded_data" not in updated
    assert "        # Clean me\n        source: data:," in updated
