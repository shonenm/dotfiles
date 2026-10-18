#!/usr/bin/env python3
"""Focused tests for the TUIOS migration, without touching live sessions."""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib
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

    def test_switch_and_create_are_owned_by_native_command(self):
        with patch.dict(os.environ, TUIOS_SESSION="current"), patch.object(tui, "sessions", side_effect=AssertionError("no preflight listing")), patch.object(tui, "switch_session") as switch:
            tui.connect("work")
        switch.assert_called_once_with("--create", "work")

    def test_project_path_is_one_argument(self):
        with patch.dict(os.environ, TUIOS_SESSION="current"), patch.object(tui, "switch_session") as switch:
            tui.connect("work", "/tmp/a b;$x")
        switch.assert_called_once_with("--create", "--cwd", "/tmp/a b;$x", "work")

    def test_remote_refusal_guides_user_to_native_picker(self):
        refused = subprocess.CompletedProcess([], 1, "", "switch-session failed: refused: switch_session came from host ailab and would change this machine, not the session")
        with patch.object(subprocess, "run", return_value=refused) as command, patch.object(tui, "run") as extra, patch.object(sys.stdin, "isatty", return_value=True), patch("builtins.print") as message, patch("builtins.input") as acknowledge:
            tui.switch_session("remote-work")
        command.assert_called_once_with(["tuios", "switch-session", "remote-work"], capture_output=True, text=True)
        message.assert_called_once_with("Session remote-work: Ctrl+Space s で選択", flush=True)
        acknowledge.assert_called_once_with("Enterで閉じる: ")
        extra.assert_not_called()

    def test_switch_errors_other_than_host_fence_remain_errors(self):
        failed = subprocess.CompletedProcess([], 1, "", "permission denied")
        with patch.object(subprocess, "run", return_value=failed), patch.object(tui, "run") as notify:
            with self.assertRaisesRegex(RuntimeError, "permission denied"):
                tui.switch_session("work")
        notify.assert_not_called()

    def test_attach_outside_uses_native_create_in_requested_directory(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(os, "chdir") as change, patch.object(os, "execvp") as execute:
            tui.connect("work", "/tmp/a b;$x")
        change.assert_called_once_with("/tmp/a b;$x")
        execute.assert_called_once_with("tuios", ["tuios", "attach", "--create", "work"])

    def test_project_picker_deduplicates_folders_without_session_listing(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            (home / "dotfiles").mkdir()
            project = home / "project with spaces"
            project.mkdir()
            result = subprocess.CompletedProcess([], 0, f"{project}\n{project}\n")
            with patch.object(Path, "home", return_value=home), patch.object(shutil, "which", return_value="installed"), patch.object(tui, "run", return_value=result), patch.object(tui, "sessions", side_effect=AssertionError("native navigator owns sessions")), patch.object(tui, "choose", return_value="2") as choose, patch.object(tui, "connect") as connect:
                tui.pick()
            self.assertEqual(len(choose.call_args.args[0]), 3)
            self.assertEqual(choose.call_args.args[1], "project")
            connect.assert_called_once_with(tui.session_name(project), str(project))

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

    def test_no_daemon_returns_valid_saved_session_listing_with_exit_three(self):
        for rows in ([], [{"name": "work", "saved": True}]):
            with self.subTest(rows=rows), patch.object(subprocess, "run", return_value=subprocess.CompletedProcess([], 3, json.dumps(rows), "")):
                self.assertEqual(tui.sessions(), rows)

    def test_other_listing_errors_surface_even_without_stderr(self):
        for stderr, message in (("permission denied", "permission denied"), ("", "tuios ls exited 1")):
            with self.subTest(stderr=stderr), patch.object(subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", stderr)):
                with self.assertRaisesRegex(RuntimeError, message):
                    tui.sessions()

    def test_no_argument_launch_delegates_to_native_last_session_or_creation(self):
        with patch.object(sys, "argv", ["tui"]), patch.dict(os.environ, {}, clear=True), patch.object(tui, "run") as run, patch.object(os, "execvp") as execute:
            self.assertEqual(tui.main(), 0)
        run.assert_not_called()
        execute.assert_called_once_with("tuios", ["tuios"])

    def test_no_argument_launch_inside_opens_native_switcher(self):
        with patch.object(sys, "argv", ["tui"]), patch.dict(os.environ, TUIOS_SESSION="work"), patch.object(tui, "run") as run:
            self.assertEqual(tui.main(), 0)
        run.assert_called_once_with("tuios", "run-command", "prefix_session_switcher")


class ShellTests(unittest.TestCase):
    def test_user_shell_forwards_commands_and_keeps_no_argument_launch(self):
        for kind in ("pixi", "nix", "chroot"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temp:
                home = Path(temp)
                if kind == "pixi":
                    executable = home / ".pixi/bin/zsh"
                elif kind == "nix":
                    executable = home / ".nix-profile/bin/zsh"
                else:
                    executable = home / ".local/bin/nix-user-chroot"
                    (home / ".nix-store/nix").mkdir(parents=True)
                executable.parent.mkdir(parents=True, exist_ok=True)
                executable.write_text('#!/bin/sh\nfor arg do printf "%s\\n" "$arg"; done > "$TEST_ARGS"\nprintf "%s" "$PATH" > "$TEST_PATH"\n')
                executable.chmod(0o755)
                env = {**os.environ, "HOME": temp, "PATH": "/usr/bin:/bin", "TEST_ARGS": str(home / "args"), "TEST_PATH": str(home / "path")}
                for args in ([], ["-lc", "printf 'space ; $value'"]):
                    subprocess.run(["bash", str(ROOT / "scripts/tmux-default-shell"), *args], env=env, check=True)
                    prefix = [str(home / ".nix-store/nix"), str(home / ".nix-profile/bin/zsh")] if kind == "chroot" else []
                    self.assertEqual((home / "args").read_text().splitlines(), prefix + args)
                    self.assertEqual((home / "path").read_text().split(":")[:3], [str(home / ".local/bin"), str(home / ".pixi/bin"), str(home / ".local/share/mise/shims")])


class ConfigTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("tuios"), "tuios not installed")
    def test_installed_release_listing_before_daemon_start(self):
        with tempfile.TemporaryDirectory() as temp:
            env = {key: value for key, value in os.environ.items() if not key.startswith("TUIOS_")}
            env.update(TUIOS_SERVER="ls-" + Path(temp).name[-8:], XDG_CONFIG_HOME=temp, XDG_CONFIG_DIRS=temp, XDG_STATE_HOME=f"{temp}/state")
            with patch.dict(os.environ, env, clear=True):
                self.assertEqual(tui.sessions(), [])

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
        self.assertEqual(bindings["prefix", "ctrl+f"], "choose_tree")
        self.assertEqual(bindings["prefix", "F"], "command:projects")
        self.assertEqual(bindings["prefix", "i"], "prefix_inbox")
        self.assertEqual(bindings["prefix.layout", "s"], "layout_prefix_save")
        self.assertEqual(bindings["prefix.layout", "l"], "layout_prefix_load")
        for key, action in {"h": "prev_session", "l": "next_session", "j": "prefix_session_switcher", "k": "last_session"}.items():
            self.assertEqual(bindings["global", f"ctrl+alt+{key}"], action)
            self.assertEqual(bindings["global", f"alt+{key}"], action)
        self.assertNotIn(("global", "ctrl+p"), bindings)

    def test_restore_project_trust_and_remote_action_placement(self):
        config = tomllib.loads((ROOT / "common/tuios/.config/tuios/config.d/dotfiles.toml").read_text())
        self.assertEqual(config["daemon"]["resume_agents"], "ask")
        self.assertEqual(config["tape"]["autorun"], "ask")
        self.assertEqual(config["appearance"]["auto_enter_terminal_on_focus"], "off")
        for entry in config["keybindings"]["command"]:
            self.assertNotIn("tui nav ", entry.get("command", ""))
            self.assertNotIn(entry["key"], [f"{modifier}{key}" for modifier in ("alt+", "ctrl+alt+") for key in "hjkl"])
            if entry["name"] in ("project-root", "projects", "session-space"):
                self.assertEqual(entry["type"], "popup", entry["name"])
        hosts = tomllib.loads((ROOT / "mac/tuios/.config/tuios/config.d/20-hosts.toml").read_text())["hosts"]
        self.assertEqual(hosts["ailab"]["addr"], "ailab")
        self.assertEqual(hosts["pi-500"]["addr"], "pi-500")

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
