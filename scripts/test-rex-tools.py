#!/usr/bin/env python3
"""Rex helper の unit test。REX_TEST_INTEGRATION=1 で専用 session を検証する。"""
import copy
import importlib.machinery
import importlib.util
import os
import signal
import tempfile
import time
from concurrent.futures import Future
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
    def snapshot(self):
        return {"version": 1, "updated": time.time(), "cwd": "/tmp/project", "host": "local", "session": "project",
                "stats": {"CPU": "25%", "RAM": "82%", "GPU": "", "Disk": "11%", "Git": "main +42/-18"},
                "usage": [{"provider": "claude", "window": "weekly", "percent": "0%", "reset": ""},
                          {"provider": "codex", "window": "", "percent": "未取得", "reset": ""}],
                "agents": [{"session": "test", "app": "pi", "state": "working", "message": "テスト中", "updated": "yesterday"}]}

    def test_metadata_cache_roundtrip_and_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cache/data.json"
            data = self.snapshot()
            tool.save_metadata_cache(path, data)
            self.assertEqual(tool.read_metadata_cache(path), data)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            path.write_text('{"version":1}')
            self.assertIsNone(tool.read_metadata_cache(path))
            path.write_text('not json')
            self.assertIsNone(tool.read_metadata_cache(path))

    def test_metadata_cache_is_scoped_to_origin(self):
        self.assertNotEqual(tool.metadata_cache("s", "a"), tool.metadata_cache("s", "b"))
        self.assertNotEqual(tool.metadata_cache("s", "a"), tool.metadata_cache("t", "a"))

    def test_usage_keeps_zero_separate_from_missing(self):
        with patch.object(tool, "command_text", return_value="icon\x1fweekly\x1fgauge\x1f0%\x1f2d"):
            self.assertEqual(tool.usage_rows("claude")[0]["percent"], "0%")
        with patch.object(tool, "command_text", return_value="icon\x1f--"):
            self.assertEqual(tool.usage_rows("claude")[0]["percent"], "未取得")

    def test_panel_narrow_layout_details_and_bar(self):
        data = self.snapshot()
        wide = tool.metadata_rows(data, 90)
        narrow = tool.metadata_rows(data, 40)
        self.assertGreater(len(narrow), len(wide))
        text = "\n".join(t for t, _ in wide)
        self.assertIn('[----------] 0%', text)
        self.assertIn('未取得', text)
        self.assertNotIn('yesterday', text)
        self.assertIn('yesterday', str(tool.metadata_rows(data, 90, True)))
        self.assertEqual(tool.cell('日本abc', 5), '日本a')

    def test_fresh_cache_draws_without_collecting(self):
        screen = Mock()
        screen.getch.return_value = ord('q')
        with patch.object(tool.curses, "curs_set"), patch.object(tool.curses, "has_colors", return_value=False), \
             patch.object(tool, "read_metadata_cache", return_value=self.snapshot()), \
             patch.object(tool, "draw_metadata", return_value=0) as draw, \
             patch.object(tool, "refresh_metadata") as collect, patch.object(tool, "api"):
            tool.screen(screen, "metadata", "s", "b")
        self.assertIsNotNone(draw.call_args_list[0].args[1])
        collect.assert_not_called()

    def test_failed_refresh_preserves_previous_snapshot(self):
        data = self.snapshot()
        data['updated'] -= 60
        future = Future()
        future.set_exception(RuntimeError('offline'))
        screen = Mock()
        screen.getch.side_effect = [-1, ord('q')]
        with patch.object(tool.curses, "curs_set"), patch.object(tool.curses, "has_colors", return_value=False), \
             patch.object(tool, "read_metadata_cache", return_value=data), \
             patch.object(tool, "draw_metadata", return_value=0) as draw, \
             patch.object(tool, "ThreadPoolExecutor") as pool, patch.object(tool, "api"):
            pool.return_value.__enter__.return_value.submit.return_value = future
            tool.screen(screen, "metadata", "s", "b")
        self.assertEqual(draw.call_args.args[1], data)
        self.assertEqual(draw.call_args.args[3], 'offline')

    def test_dev_action_dispatches_without_prefix_menu(self):
        with patch.object(tool.sys, "argv", ["rex-tools", "view", "dev", "--session", "s", "--block", "b"]), \
             patch.dict(os.environ, {"REX_SERVER": ""}), \
             patch.object(tool, "origin", return_value="anchor"), patch.object(tool, "template") as template:
            tool.main()
        template.assert_called_once_with("s", "anchor")

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
    def test_loaded_native_prefix_keymap(self):
        bindings = {tuple(b["keys"]): b for b in tool.rex("keymap", "--json")["bindings"]}
        self.assertNotIn(("ctrl+space",), bindings)
        for key, kind in tool.POPUPS.items():
            key = "shift+" + key.lower() if key.isupper() else key
            self.assertEqual(bindings[("ctrl+space", key)]["action"], "dotfiles_" + kind)
        self.assertEqual(bindings[("ctrl+space", "c")]["action"], "client.tab.new")
        self.assertEqual(bindings[("ctrl+space", "shift+/")]["action"], "dotfiles_prefix")
        self.assertEqual(bindings[("ctrl+space", "ctrl+space")]["args"], {"key": "ctrl+space"})
        self.assertEqual(bindings[("ctrl+space", "shift+n")]["action"], "dotfiles_dev")

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
