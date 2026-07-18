#!/usr/bin/env python3

import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("check-markdown-links.py")
SPEC = importlib.util.spec_from_file_location("check_markdown_links", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class MarkdownLinkCheckTest(unittest.TestCase):
    def test_ignores_code_and_supports_angle_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "exists.md").touch()
            (root / "dir").mkdir()
            (root / "dir/file name.md").touch()
            (root / "a(b).md").touch()
            source = root / "README.md"
            source.write_text(
                "[ok](exists.md)\n"
                "`[inline](missing-inline.md)`\n"
                "~~~md\n[fenced](missing-fenced.md)\n"
                "~~~not-a-close\n[still-fenced](missing-too.md)\n~~~\n"
                "[space](<dir/file name.md>)\n"
                "[parentheses](a(b).md)\n"
                "[bad](missing.md)\n"
            )

            self.assertEqual(
                MODULE.find_missing([source], root),
                ["README.md:10: missing.md"],
            )

    def test_ignores_external_anchor_and_custom_scheme(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "README.md"
            source.write_text("[web](https://example.com) [anchor](#x) [color](fg:cyan)\n")
            self.assertEqual(MODULE.find_missing([source], root), [])


if __name__ == "__main__":
    unittest.main()
