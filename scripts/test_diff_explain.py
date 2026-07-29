#!/usr/bin/env python3

from importlib.machinery import SourceFileLoader
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).with_name("diff-explain")
SPEC = importlib.util.spec_from_loader(
    "diff_explain", SourceFileLoader("diff_explain", str(SCRIPT))
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)

DIFF = """diff --git a/app/main.py b/app/main.py
index 1111111..2222222 100644
--- a/app/main.py
+++ b/app/main.py
@@ -1,4 +1,5 @@ def run():
 import os
-import sys
+import json
+import time
     return None
@@ -20,2 +21,2 @@
-old = 1
+new = 1
diff --git a/logo.png b/logo.png
index 3333333..4444444 100644
Binary files a/logo.png and b/logo.png differ
"""


class ParseDiffTest(unittest.TestCase):
    def setUp(self):
        self.files = MODULE.parse_diff(DIFF)

    def test_files_and_hunks(self):
        self.assertEqual([f["path"] for f in self.files], ["app/main.py", "logo.png"])
        self.assertEqual(len(self.files[0]["hunks"]), 2)
        self.assertTrue(self.files[1]["binary"])
        self.assertEqual(self.files[1]["hunks"], [])

    def test_line_numbering(self):
        lines = self.files[0]["hunks"][0]["lines"]
        self.assertEqual(
            [(kind, old, new) for kind, old, new, _ in lines],
            [
                ("ctx", 1, 1),
                ("del", 2, None),
                ("add", None, 2),
                ("add", None, 3),
                ("ctx", 3, 4),
            ],
        )
        self.assertEqual(self.files[0]["hunks"][1]["lines"][0][1], 20)

    def test_side_by_side_pairs_del_with_add(self):
        rows = MODULE.side_by_side(self.files[0]["hunks"][0]["lines"])
        self.assertEqual(
            [(left and left[2], right and right[2]) for left, right in rows],
            [
                ("import os", "import os"),
                ("import sys", "import json"),
                (None, "import time"),  # 追加が余る行は左が空
                ("    return None", "    return None"),
            ],
        )

    def test_render_places_note_with_matching_hunk(self):
        explain = {"hunks": {"app/main.py#2": "2番目の hunk の解説"}, "files": {}}
        page = MODULE.render_html(self.files, explain, "T", "range")
        self.assertIn("2番目の hunk の解説", page)
        self.assertLess(page.index("app/main.py#2"), page.index("2番目の hunk の解説"))
        self.assertIn("&lt;", MODULE.rich_text("<script>"))


class SplitHunkTest(unittest.TestCase):
    def hunk(self, bodies):
        lines = [("add", None, i, body) for i, body in enumerate(bodies, 1)]
        return {"header": "@@ -0,0 +1,%d @@" % len(lines), "context": "", "lines": lines}

    def test_splits_before_top_level_definition(self):
        # def の直前 (空行を挟んでも) で切れ、関数の途中では切れないこと
        body = lambda i: ["def f%d():" % i, "    a = 1", "    b = 2", "    return a", ""]
        parts = MODULE.split_hunk(self.hunk(body(1) + body(2) + body(3)), 4)
        self.assertEqual([p["lines"][0][3] for p in parts], ["def f1():", "def f2():", "def f3():"])
        self.assertEqual(parts[1]["header"], "@@ -0,0 +6,5 @@")

    def test_forces_split_without_top_level_lines(self):
        parts = MODULE.split_hunk(self.hunk(["    x"] * 25), 4)
        self.assertTrue(all(len(p["lines"]) <= 8 for p in parts))
        self.assertEqual(sum(len(p["lines"]) for p in parts), 25)

    def test_short_hunk_and_disabled_split_are_untouched(self):
        hunk = self.hunk(["x"] * 10)
        self.assertEqual(MODULE.split_hunk(hunk, 40), [hunk])
        self.assertEqual(MODULE.split_hunk(hunk, 0), [hunk])


class GuessLangTest(unittest.TestCase):
    def test_extension_filename_and_shebang(self):
        self.assertEqual(MODULE.guess_lang("a/b/main.py", []), "python")
        self.assertEqual(MODULE.guess_lang("Dockerfile", []), "dockerfile")
        shebang = [{"lines": [("add", None, 1, "#!/usr/bin/env python3")]}]
        self.assertEqual(MODULE.guess_lang("scripts/diff-explain", shebang), "python")
        self.assertEqual(MODULE.guess_lang("scripts/unknown-thing", []), "")


if __name__ == "__main__":
    unittest.main()
