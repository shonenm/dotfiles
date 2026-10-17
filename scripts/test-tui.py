#!/usr/bin/env python3
"""Focused tests for the TUIOS migration, without touching live sessions."""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("tui", str(ROOT / "scripts/tui"))
spec = importlib.util.spec_from_loader(loader.name, loader)
tui = importlib.util.module_from_spec(spec)
loader.exec_module(tui)


class SessionTests(unittest.TestCase):
    def test_project_names_are_stable_safe_and_distinct(self):
        self.assertEqual(tui.session_name("/tmp/a/project"), tui.session_name("/tmp/a/project"))
        self.assertNotEqual(tui.session_name("/tmp/a/project"), tui.session_name("/tmp/b/project"))
        self.assertRegex(tui.session_name("/tmp/日本語 project;$(x)"), r"^[a-zA-Z0-9_-]+$")

    def test_existing_session_switches_without_recreating(self):
        with patch.dict(os.environ, TUIOS_SESSION="current"), patch.object(tui, "sessions", return_value=[{"name": "work"}]), patch.object(tui, "run") as run:
            tui.connect("work")
        run.assert_called_once_with("tuios", "switch-session", "work")

    def test_new_session_preserves_path_as_one_argument(self):
        with patch.dict(os.environ, TUIOS_SESSION="current"), patch.object(tui, "sessions", return_value=[]), patch.object(tui, "run") as run:
            tui.connect("work", "/tmp/a b;$x")
        self.assertEqual(run.call_args_list[0].args, ("tuios", "new", "work", "--detach", "--cwd", "/tmp/a b;$x"))
        self.assertEqual(run.call_args_list[1].args, ("tuios", "switch-session", "work"))

    def test_navigation_stays_in_space_and_wraps(self):
        rows = [
            {"name": "a", "space": "code", "last_active": 1},
            {"name": "b", "space": "code", "last_active": 2},
            {"name": "c", "space": "ops", "last_active": 3},
            {"name": "d", "space": "ops", "last_active": 4},
        ]
        with patch.dict(os.environ, TUIOS_SESSION="a"), patch.object(tui, "sessions", return_value=rows), patch.object(tui, "run") as run:
            tui.navigate("prev")
            self.assertEqual(run.call_args.args, ("tuios", "switch-session", "b"))
            tui.navigate("next-group")
            self.assertEqual(run.call_args.args, ("tuios", "switch-session", "d"))

    def test_native_space_named_clear_is_not_a_menu_action(self):
        with patch.object(tui, "sessions", return_value=[{"space": "clear"}]), patch.object(tui, "choose", return_value="group:clear"), patch.object(tui, "run") as run:
            tui.group()
        run.assert_called_once_with("tuios", "set-session-space", "clear")

    def test_create_space_named_clear(self):
        with patch.object(tui, "sessions", return_value=[]), patch.object(tui, "choose", return_value="new"), patch("builtins.input", return_value="clear"), patch.object(tui, "run") as run:
            tui.group()
        run.assert_called_once_with("tuios", "set-session-space", "clear")

    def test_full_workspace_does_not_type_into_existing_program(self):
        full = subprocess.CompletedProcess([], 0, json.dumps({"workspaces": [{"window_count": 1}]}))
        with patch.object(tui, "run", return_value=full) as run:
            with self.assertRaisesRegex(RuntimeError, "every workspace"):
                tui.dev()
        self.assertEqual(run.call_count, 1)

    def test_no_daemon_is_empty_but_other_errors_surface(self):
        with patch.object(subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "The TUIOS daemon is not running")):
            self.assertEqual(tui.sessions(), [])
        with patch.object(subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "permission denied")):
            with self.assertRaisesRegex(RuntimeError, "permission denied"):
                tui.sessions()


class ConfigTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("tuios"), "tuios not installed")
    def test_installed_release_accepts_keys_without_collisions(self):
        with tempfile.TemporaryDirectory() as temp:
            config = Path(temp) / "tuios"
            (config / "config.d").mkdir(parents=True)
            (config / "config.toml").touch()
            shutil.copy(ROOT / "common/tuios/.config/tuios/config.d/dotfiles.toml", config / "config.d/dotfiles.toml")
            env = {**os.environ, "XDG_CONFIG_HOME": temp, "XDG_CONFIG_DIRS": temp}
            result = subprocess.run(["tuios", "keybinds", "doctor", "--json"], env=env, capture_output=True, text=True, check=True)
            report = json.loads(result.stdout)
        self.assertEqual(report["leader"], "ctrl+space")
        for field in ("key_problems", "command_problems", "copy_mode_problems", "collisions"):
            self.assertFalse(report[field], f"{field}: {report[field]}")
        bindings = {(r["scope"], r["key"]): r["action"] for r in report["bindings"] if not r["shadowed"]}
        for key, action in {"c": "new_workspace", "n": "next_workspace", "p": "prev_workspace", "T": "rename_workspace", "9": "command:project-root", "g": "command:lazygit", "j": "toggle_scratch", "G": "command:live-pr", "space": "prefix_file_search"}.items():
            self.assertEqual(bindings["prefix", key], action)
        self.assertEqual(bindings["terminal", "ctrl+h"], "terminal_focus_left")
        self.assertNotIn(("global", "ctrl+p"), bindings)

    @unittest.skipUnless(shutil.which("tuios"), "tuios not installed")
    def test_installer_preserves_tmux_hooks_and_is_idempotent(self):
        installer = (ROOT / "install.sh").read_text()
        function = "setup_tuios() {" + installer.split("setup_tuios() {", 1)[1].split("\n}", 1)[0] + "\n}"
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            (home / ".claude").mkdir()
            (home / ".pi/agent").mkdir(parents=True)
            settings = home / ".claude/settings.json"
            settings.write_text((ROOT / "templates/claude-settings.json").read_text().replace("__HOME__", temp))
            env = {**os.environ, "HOME": temp, "XDG_CONFIG_HOME": f"{temp}/.config", "XDG_CONFIG_DIRS": f"{temp}/.config", "PI_CODING_AGENT_DIR": f"{temp}/.pi/agent", "DOTFILES_DIR": str(ROOT)}
            script = "command_exists() { command -v \"$1\" >/dev/null; }; log_warn() { :; }; log_error() { :; }; SETUP_FAILED=false;\n" + function + "\nsetup_tuios; [[ $SETUP_FAILED == false ]]"
            for _ in range(2):
                subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True, check=True)
                data = json.loads(settings.read_text())
                hooks = [hook["command"] for entry in data["hooks"]["SessionStart"] for hook in entry["hooks"]]
                self.assertTrue(any("tmux-claude-pane.sh track claude" in hook for hook in hooks))
                self.assertEqual(sum("agent-hook" in hook for hook in hooks), 1)
            self.assertEqual(data["statusLine"]["command"], f"{temp}/.claude/statusline-command.sh")
            self.assertTrue((home / ".pi/agent/extensions/tuios-agent-state.ts").is_file())
            self.assertTrue((home / ".config/tuios/config.toml").is_file())

    @unittest.skipUnless(shutil.which("nvim"), "nvim not installed")
    def test_neovim_internal_edge_and_tmux_navigation(self):
        lua = r'''
local reports = {}
local stdout = io.stdout
io.stdout = { write = function(_, s) reports[#reports + 1] = s end, flush = function() end }
vim.env.TUIOS_ENV = "1"
local spec = dofile(vim.env.NAV_CONFIG)
spec.config()
vim.wait(20)
assert(table.concat(reports):find("state;active", 1, true))
local left = vim.api.nvim_get_current_win()
vim.cmd("vsplit")
vim.cmd("wincmd H")
local first = vim.api.nvim_get_current_win()
local count = #reports
spec.keys[4][2]() -- right, inside Neovim
assert(vim.api.nvim_get_current_win() ~= first)
assert(#reports == count)
spec.keys[4][2]() -- right, Neovim edge
assert(reports[#reports]:find("focus;right", 1, true))
vim.api.nvim_exec_autocmds("VimSuspend", {})
assert(reports[#reports]:find("state;inactive", 1, true))
vim.api.nvim_exec_autocmds("VimResume", {})
assert(reports[#reports]:find("state;active", 1, true))
vim.api.nvim_del_augroup_by_name("TuiosNavigator")
vim.env.TUIOS_ENV = nil
local moved = false
vim.api.nvim_create_user_command("TmuxNavigateLeft", function() moved = true end, {})
spec = dofile(vim.env.NAV_CONFIG)
spec.keys[1][2]()
assert(moved)
io.stdout = stdout
vim.cmd("qa!")
'''
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "test.lua"
            path.write_text(lua)
            env = {**os.environ, "NAV_CONFIG": str(ROOT / "common/nvim/.config/nvim/lua/plugins/tmux-navigator.lua")}
            subprocess.run(["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", str(path)], env=env, capture_output=True, text=True, check=True, timeout=20)


if __name__ == "__main__":
    unittest.main()
