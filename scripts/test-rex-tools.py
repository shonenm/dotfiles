#!/usr/bin/env python3
"""Rex helper の unit test。REX_TEST_INTEGRATION=1 で専用 session を検証する。"""
import copy
import importlib.machinery
import importlib.util
import os
import signal
import time
from pathlib import Path
import unittest
from unittest.mock import Mock, patch
import uuid

loader = importlib.machinery.SourceFileLoader("rex_tools", str(Path(__file__).with_name("rex-tools")))
spec = importlib.util.spec_from_loader(loader.name, loader)
tool = importlib.util.module_from_spec(spec)
loader.exec_module(tool)


def split(a="a", b="b", ratio=.6):
    return {"split": {"direction": "horizontal", "ratio": ratio,
                      "before": {"block_id": a}, "after": {"block_id": b}}}


class UnitTests(unittest.TestCase):
    def test_prefix_ignores_resize_until_user_key(self):
        for key in (27, ord("g")):
            with self.subTest(key=key):
                screen = Mock()
                screen.getch.side_effect = [-1, tool.curses.KEY_RESIZE, tool.curses.KEY_RESIZE, key]
                with patch.object(tool.curses, "curs_set"), patch.object(tool, "draw") as draw:
                    self.assertEqual(tool.screen(screen, "prefix", "s", "b"), key)
                self.assertEqual(draw.call_count, 4)

    def test_plain_removes_terminal_and_tmux_controls(self):
        self.assertEqual(tool.plain("\x1b[31mred\x1b[0m#[fg=red]\x1f20%\x07"), "red  20%")

    def test_layout_shape_ignores_ids_and_ratio(self):
        self.assertEqual(tool.shape(split()), tool.shape(split("c", "d", .4)))

    def test_restore_changes_only_ratio(self):
        with patch.object(tool, "api") as api:
            tool.restore_layout("s", split("c", "d", .4), split())
        api.assert_called_once_with("s", "session.resize_pane", direction="horizontal",
                                    before_block_id="c", after_block_id="d", ratio=.6)

    def test_restore_rejects_topology_before_any_mutation(self):
        with patch.object(tool, "api") as api:
            with self.assertRaises(RuntimeError):
                tool.restore_layout("s", {"block_id": "a"}, split())
        api.assert_not_called()

    def test_cwd_decodes_osc7(self):
        with patch.object(tool, "terminal", return_value={"pwd": "file://localhost/tmp/a%20b"}), \
             patch.object(Path, "is_dir", return_value=True):
            self.assertEqual(tool.cwd_for("s", "b"), "/tmp/a b")

    def test_cwd_missing_is_not_home_fallback(self):
        with patch.object(tool, "terminal", return_value={}):
            with self.assertRaises(RuntimeError):
                tool.cwd_for("s", "b")

    def test_popup_from_popup_resolves_original(self):
        with patch.object(tool, "blocks", return_value=[{"block_id": "p", "label": tool.TAG + "prefix/block:source"}]):
            self.assertEqual(tool.origin("s", "p"), "block:source")

    def test_toggle_preserves_process(self):
        entries = [{"block_id": "a", "label": "shell", "placement": "placed", "window_id": "w"},
                   {"block_id": "p", "label": tool.TAG + "scratch/a", "placement": "placed"}]
        with patch.object(tool, "blocks", return_value=entries), patch.object(tool, "api") as api:
            tool.popup("scratch", "s", "a")
        self.assertEqual([c.args[1] for c in api.call_args_list], ["session.detach_block", "session.focus_block"])

    def test_prefix_twice_closes_menu_and_sends_key(self):
        entries = [{"block_id": "a", "label": "shell", "placement": "placed", "window_id": "w"},
                   {"block_id": "p", "label": tool.TAG + "prefix/a", "placement": "placed"}]
        with patch.object(tool, "blocks", return_value=entries), patch.object(tool, "api") as api, \
             patch.object(tool, "rex") as rex:
            tool.popup("prefix", "s", "p")
        self.assertEqual([c.args[1] for c in api.call_args_list], ["block.close", "session.focus_block"])
        rex.assert_called_once_with("send-key", "-s", "s", "-b", "a", "ctrl+space")

    def test_reopen_same_block(self):
        entries = [{"block_id": "a", "label": "shell", "placement": "placed", "window_id": "w"},
                   {"block_id": "p", "label": tool.TAG + "scratch/a", "placement": "detached"}]
        with patch.object(tool, "blocks", return_value=entries), patch.object(tool, "api") as api:
            tool.popup("scratch", "s", "a")
        self.assertEqual([c.args[1] for c in api.call_args_list],
                         ["session.move_block", "session.float_block", "session.focus_block"])
        self.assertTrue(all(c.kwargs["block_id"] == "p" for c in api.call_args_list))

    def test_new_popup_uses_anchor_window_cwd_and_size(self):
        entries = [{"block_id": "a", "label": "shell", "placement": "placed", "window_id": "w"}]
        with patch.object(tool, "blocks", return_value=entries), \
             patch.object(tool, "cwd_for", return_value="/tmp/project"), patch.object(tool, "api") as api:
            tool.popup("git", "s", "a")
        args = api.call_args.kwargs
        self.assertEqual(args["window_id"], "w")
        self.assertEqual(args["layout"]["block"]["options"], {"cwd": "/tmp/project", "command": ["lazygit"]})
        self.assertEqual(args["bounds"][2:], [.8, .8])

    def test_unknown_popup_fails(self):
        with self.assertRaises(RuntimeError):
            tool.popup("typo", "s", "a")


@unittest.skipUnless(os.environ.get("REX_TEST_INTEGRATION") == "1", "opt-in Rex integration")
class IntegrationTests(unittest.TestCase):
    def test_lifecycle_and_layout(self):
        created = tool.rex("new", "dotfiles-rex-test-" + uuid.uuid4().hex[:8], "--cwd", "/tmp", "--json")
        session = created["session_id"]
        anchor = created["initial_windows"][0]["block_ids"][0]
        try:
            # cwd は prompt よりも process API で取得できる。
            tool.popup("scratch", session, anchor)
            popup = next(b for b in tool.blocks(session) if b["label"].startswith(tool.TAG))
            pid = tool.terminal(session, popup["block_id"], "process")["child"]["pid"]
            tool.popup("scratch", session, popup["block_id"])
            self.assertEqual(next(b for b in tool.blocks(session) if b["block_id"] == popup["block_id"])["placement"], "detached")
            tool.popup("scratch", session, anchor)
            self.assertEqual(tool.terminal(session, popup["block_id"], "process")["child"]["pid"], pid)
            self.assertEqual(len([b for b in tool.blocks(session) if b["label"].startswith(tool.TAG)]), 1)
            tool.api(session, "session.new_split", anchor_id=anchor, direction="horizontal", side="after", ratio=.65,
                     layout={"block": {"flavor": tool.TERMINAL + ".shell"}})
            original = tool.tiled_layout(session, anchor)
            changed = copy.deepcopy(original)
            changed["split"]["ratio"] = .4
            tool.restore_layout(session, original, changed)
            self.assertAlmostEqual(tool.tiled_layout(session, anchor)["split"]["ratio"], .4)
            tool.restore_layout(session, tool.tiled_layout(session, anchor), original)
            self.assertAlmostEqual(tool.tiled_layout(session, anchor)["split"]["ratio"], .65)
            tool.popup("prefix", session, anchor)
            menu = next(b for b in tool.blocks(session) if b["label"].startswith(tool.TAG + "prefix/"))
            deadline = time.monotonic() + 5
            captured = ""
            while time.monotonic() < deadline:
                captured = tool.run([tool.rex_binary(), "capture", "-s", session, "-b", menu["block_id"], "--trim"]).stdout
                if "PREFIX" in captured:
                    break
                time.sleep(.05)
            self.assertIn("PREFIX", captured)
            # GUI が popup の寸法を通知したときと同じ resize signal。
            menu_pid = tool.terminal(session, menu["block_id"], "process")["child"]["pid"]
            os.kill(menu_pid, signal.SIGWINCH)
            waiting = tool.run([tool.rex_binary(), "wait", menu["block_id"], "-s", session, "--for", "300ms"])
            self.assertIn("wait timed out", waiting.stderr)
            self.assertTrue(any(b["block_id"] == menu["block_id"] for b in tool.blocks(session)))
            tool.rex("send-key", "-s", session, "-b", menu["block_id"], "escape")
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if not any(b["block_id"] == menu["block_id"] for b in tool.blocks(session)):
                    break
                time.sleep(.05)
            self.assertFalse(any(b["block_id"] == menu["block_id"] for b in tool.blocks(session)))
        finally:
            tool.api(session, "session.destroy")


if __name__ == "__main__":
    unittest.main()
