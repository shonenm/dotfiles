#!/usr/bin/env python3
"""Focused tests for the TUIOS migration, without touching live sessions."""

import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
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

    def test_space_command_sets_native_membership(self):
        rows = [{"space": "work"}, {"space": "work"}, {"space": "personal"}, {"space": ""}]
        with patch.object(sys, "argv", ["tui", "space"]), patch.object(tui, "sessions", return_value=rows), patch.object(tui, "choose", return_value="space:work") as choose, patch.object(tui, "run") as run:
            self.assertEqual(tui.main(), 0)
        choose.assert_called_once_with(["new\tCreate space", "clear\tRemove from space", "space:personal\tpersonal", "space:work\twork"], "space")
        run.assert_called_once_with("tuios", "set-session-space", "work")

    def test_native_space_named_clear_is_not_a_menu_action(self):
        with patch.object(tui, "sessions", return_value=[{"space": "clear"}]), patch.object(tui, "choose", return_value="space:clear"), patch.object(tui, "run") as run:
            tui.space()
        run.assert_called_once_with("tuios", "set-session-space", "clear")

    def test_create_space_named_clear(self):
        with patch.object(tui, "sessions", return_value=[]), patch.object(tui, "choose", return_value="new"), patch("builtins.input", return_value="clear"), patch.object(tui, "run") as run:
            tui.space()
        run.assert_called_once_with("tuios", "set-session-space", "clear")

    def test_space_navigation_wraps_and_uses_native_activity_and_client_identity(self):
        rows = [
            {"name": "unfiled", "last_active": 1},
            {"name": "renamed-a", "space": "code", "last_active": 2},
            {"name": "code-b", "space": "code", "last_active": 4},
            {"name": "ops-b", "space": "ops", "last_active": 6},
            {"name": "ops-a", "space": "ops", "last_active": 6},
        ]
        for current, direction, target in (("renamed-a", "next", "ops-a"), ("renamed-a", "prev", "unfiled"), ("ops-b", "next", "unfiled"), ("unfiled", "next", "code-b"), ("unfiled", "prev", "ops-a")):
            clients = [{"pid": 42, "session": current, "client_id": "own"}, {"pid": 43, "session": current, "client_id": "other"}, {"pid": 42, "session": "", "client_id": "cache"}]
            result = subprocess.CompletedProcess([], 0, json.dumps(clients))
            with self.subTest(current=current, direction=direction), patch.dict(os.environ, TUIOS_SESSION="stale-name"), patch.object(tui, "sessions", return_value=rows), patch.object(tui, "run", return_value=result) as run:
                tui.navigate_space(direction, 42)
            self.assertEqual(run.call_count, 2)
            run.assert_called_with("tuios", "switch-session", "--client", "own", target)

    def test_space_navigation_does_not_switch_another_client_while_remote(self):
        clients = [{"pid": 42, "session": "", "client_id": "remote-stream"}, {"pid": 43, "session": "work", "client_id": "other"}]
        result = subprocess.CompletedProcess([], 0, json.dumps(clients))
        with patch.object(tui, "sessions", side_effect=AssertionError("do not navigate another client's sessions")), patch.object(tui, "run", return_value=result) as run:
            tui.navigate_space("next", 42)
        run.assert_called_once_with("tuios", "list-clients", "--json", capture_output=True, text=True)

    def test_space_navigation_leaves_a_single_space_unchanged(self):
        clients = [{"pid": 42, "session": "one", "client_id": "own"}]
        result = subprocess.CompletedProcess([], 0, json.dumps(clients))
        with patch.object(tui, "sessions", return_value=[{"name": "one", "space": "code"}, {"name": "two", "space": "code"}]), patch.object(tui, "run", return_value=result) as run:
            tui.navigate_space("next", 42)
        self.assertEqual(run.call_count, 1)

    def test_space_navigation_refuses_ambiguous_client_identity(self):
        clients = [{"pid": 42, "session": "one"}, {"pid": 42, "session": "two"}]
        result = subprocess.CompletedProcess([], 0, json.dumps(clients))
        with patch.object(tui, "run", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "one attached session"):
                tui.navigate_space("next", 42)

    def test_theme_sets_the_picked_theme_on_this_client(self):
        listing = subprocess.CompletedProcess([], 0, "tokyonight\ngruvbox_dark\n")
        with patch.object(tui, "run", return_value=listing) as run, patch.object(tui, "choose", return_value="gruvbox_dark") as choose:
            tui.theme()
        choose.assert_called_once_with(["tokyonight\ttokyonight", "gruvbox_dark\tgruvbox_dark"], "theme")
        run.assert_called_with("tuios", "run-command", "SetTheme", "gruvbox_dark")

    def test_swap_picks_source_and_target_among_workspace_panes_including_focus(self):
        windows = [
            {"window_id": "scratch", "index": 0, "title": "scratch", "workspace": 1000},
            {"window_id": "a", "index": 1, "title": "~/src", "display_name": "editor", "workspace": 1},
            {"window_id": "m", "index": 2, "title": "hidden", "workspace": 1, "minimized": True},
            {"window_id": "c", "index": 3, "title": "other", "workspace": 2},
            {"window_id": "b", "index": 4, "title": "shell", "workspace": 1},
            {"window_id": "d", "index": 5, "title": "logs", "workspace": 1},
            {"window_id": "popup", "index": 6, "title": "Swap", "workspace": 1, "floating": True},
        ]
        listing = subprocess.CompletedProcess([], 0, json.dumps({"windows": windows}))
        env = {"TUIOS_ACTIVE_PANE_ID": "b", "TUIOS_SESSION": "work", "HERDR_BIN_PATH": "/herdr"}
        with patch.dict(os.environ, env), patch.object(tui, "run", return_value=listing) as run, patch.object(tui, "choose", side_effect=["b", "d"]) as choose:
            tui.swap()
        self.assertEqual([c.args for c in choose.call_args_list], [
            (["a\t1: editor", "b\t2: shell (focus)", "d\t3: logs"], "swap src"),
            (["a\t1: editor", "d\t3: logs"], "swap dst"),
        ])
        run.assert_any_call("/herdr", "pane", "swap", "--source-pane", "b", "--target-pane", "d")
        run.assert_called_with("tuios", "focus-window", "-s", "work", "b", capture_output=True)

    def test_swap_cancelled_source_swaps_nothing(self):
        listing = subprocess.CompletedProcess([], 0, json.dumps({"windows": [{"window_id": "a", "index": 0, "title": "x", "workspace": 1}]}))
        env = {"TUIOS_ACTIVE_PANE_ID": "a", "TUIOS_SESSION": "work", "HERDR_BIN_PATH": "/herdr"}
        with patch.dict(os.environ, env), patch.object(tui, "run", return_value=listing) as run, patch.object(tui, "choose", return_value=None) as choose:
            tui.swap()
        choose.assert_called_once()
        self.assertEqual(run.call_count, 1)

    def test_usage_draws_ai_usage_records_with_pace_like_tmux_sidebar(self):
        outputs = {
            "claude": "C\x1fcurrent\x1fG\x1f46%\x1f3h20m\nC\x1fweekly\x1fG\x1f30%\x1f3d12h\n",
            "codex": "X\x1f--\n",
        }
        with patch.object(tui, "ai_usage", side_effect=lambda p: outputs.get(p, "")), patch("sys.stdout", new_callable=io.StringIO) as out:
            tui.usage()
        claude, codex = "\033[38;2;255;102;0m", "\033[38;2;125;211;252m"
        self.assertEqual(out.getvalue().splitlines(), [
            f"{claude}C\033[0m \033[2mcurrent\033[0m",
            f"  {claude}G 46%\033[0m  \033[2m3h20m\033[0m",
            "  \033[2mweekly\033[0m",
            f"  {claude}G 30%\033[0m  \033[38;5;208m3d12h\033[0m \033[38;5;208m●\033[0m",
            f"{codex}X\033[0m \033[2m--\033[0m",
        ])

    def test_pace_color_skips_early_window_and_marks_used_up(self):
        self.assertEqual(tui.pace_color(10, "weekly", "6d23h"), "")
        self.assertEqual(tui.pace_color(100, "current", "1h"), "\033[38;5;39m")
        self.assertEqual(tui.pace_color(10, "current", "1h"), "\033[38;5;203m")
        self.assertEqual(tui.pace_color(50, "unknown", "1h"), "")

    def test_confirm_closes_only_after_yes(self):
        windows = [{"window_id": "a", "title": "~/src", "display_name": "editor", "workspace": 3}]
        listing = subprocess.CompletedProcess([], 0, json.dumps({"windows": windows}))
        env = {"TUIOS_ACTIVE_PANE_ID": "a", "TUIOS_SESSION": "work"}
        for target, answer, closed in (("pane", "y", ("tuios", "close-window", "a", "-s", "work")), ("workspace", "Y", ("tuios", "close-workspace", "3", "-s", "work")), ("pane", "n", None), ("workspace", "", None)):
            with self.subTest(target=target, answer=answer), patch.dict(os.environ, env), patch.object(tui, "run", return_value=listing) as run, patch("builtins.input", return_value=answer) as ask:
                tui.confirm(target)
            ask.assert_called_once_with("kill-pane editor? (y/n) " if target == "pane" else "kill-workspace 3? (y/n) ")
            if closed:
                run.assert_called_with(*closed, capture_output=True)
            else:
                self.assertEqual(run.call_count, 1)

    def test_mode_zoom_and_reload_pick_the_border_theme_by_zoom_state(self):
        env = {"TUIOS_SESSION": "work", "TUIOS_ACTIVE_PANE_ID": "p", "TUIOS_SOCKET": "/run/tuios.sock"}
        for action, zoomed, theme in (("zoom", True, "tokyonight-tmux-zoom"), ("zoom", False, "tokyonight-tmux"), ("reload", True, "tokyonight-tmux-zoom")):
            layout = subprocess.CompletedProcess([], 0, json.dumps({"result": {"layout": {"zoomed": zoomed}}}))
            with self.subTest(action=action, zoomed=zoomed), patch.dict(os.environ, env), patch.object(tui, "run", return_value=layout) as run, patch.object(tui.time, "sleep"):
                tui.mode(action)
            calls = [c.args for c in run.call_args_list]
            self.assertIn(("/run/herdr/bin/herdr", "pane", "layout", "--pane", "p"), calls)
            self.assertEqual(calls[-1], ("tuios", "run-command", "-s", "work", "SetTheme", theme))
            if action == "reload":
                self.assertEqual(calls[:2], [("tuios", "run-command", "-s", "work", "SetTheme", "tokyonight-tmux-reload"), ("tuios", "run-command", "-s", "work", "reload_config")])
            else:
                self.assertEqual(calls[0], ("tuios", "run-command", "-s", "work", "prefix_fullscreen"))

    def test_dock_branch_follows_focused_pane_of_client_session(self):
        with tempfile.TemporaryDirectory() as repo, tempfile.TemporaryDirectory() as plain:
            subprocess.run(["git", "init", "-q", "-b", "live", repo], check=True)
            panes = [{"focused": False, "cwd": plain}, {"focused": True, "cwd": repo}]
            listing = subprocess.CompletedProcess([], 0, json.dumps({"agents": panes}))
            with patch.dict(os.environ, TUIOS_SESSION="work"), patch.object(tui, "run", return_value=listing) as run, patch("sys.stdout", new_callable=io.StringIO) as out:
                tui.dock("branch")
        run.assert_called_once_with("tuios", "list-agents", "--all", "-s", "work", "--json", capture_output=True, text=True)
        self.assertEqual(out.getvalue(), " live\n")

    def test_dock_hides_gpu_without_a_reader_and_colours_storage_by_threshold(self):
        with patch.object(tui, "gpu_percent", return_value=None), patch("sys.stdout", new_callable=io.StringIO) as out:
            tui.dock("gpu")
        self.assertEqual(out.getvalue(), "")
        usage = shutil._ntuple_diskusage(100, 92, 8)
        with patch.object(tui.shutil, "disk_usage", return_value=usage), patch("sys.stdout", new_callable=io.StringIO) as out:
            tui.dock("storage")
        self.assertEqual(out.getvalue(), " \033[38;2;224;175;104m92%\033[0m\n")

    def test_dock_agents_counts_session_agents_and_marks_hang(self):
        panes = [
            {"state": "working", "harness_id": "claude-code", "evidence_age_ms": 120_000},
            {"state": "working", "harness_id": "pi", "evidence_age_ms": 119_999},
            {"state": "needs_input", "harness_id": "pi", "evidence_age_ms": 999_999},
            {"state": "none", "harness_id": "", "evidence_age_ms": None},
        ]
        listing = subprocess.CompletedProcess([], 0, json.dumps({"agents": panes}))
        with patch.dict(os.environ, TUIOS_SESSION="work"), patch.object(tui, "run", return_value=listing) as run, patch("sys.stdout", new_callable=io.StringIO) as out:
            tui.dock("agents")
        run.assert_called_once_with("tuios", "list-agents", "--all", "-s", "work", "--json", capture_output=True, text=True)
        self.assertEqual(out.getvalue(), "󰚩 3 \033[35m●\033[0m\033[33m●\033[0m\033[31m●\033[0m\n")

    def test_dock_agents_hides_cell_without_agents(self):
        listing = subprocess.CompletedProcess([], 0, json.dumps({"agents": [{"state": "none", "harness_id": ""}]}))
        with patch.dict(os.environ, TUIOS_SESSION="work"), patch.object(tui, "run", return_value=listing), patch("sys.stdout", new_callable=io.StringIO) as out:
            tui.dock("agents")
        self.assertEqual(out.getvalue(), "")

    def test_rcon_registers_container_before_creating_the_session(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, XDG_STATE_HOME=temp), patch.object(tui, "switch_session") as switch:
            switch.side_effect = lambda *args: self.assertEqual((Path(temp) / "tuios-rcon/my-app-dev").read_text(), "my.app:dev\n")
            tui.rcon("local:my.app:dev")
        switch.assert_called_once_with("--create", "my-app-dev")

    def test_rcon_registers_on_the_host_over_its_ssh_address(self):
        hosts = subprocess.CompletedProcess([], 0, json.dumps({"hosts": [{"host": "lab", "addr": "lab.example"}]}))
        with patch.object(tui, "run", return_value=hosts) as run, patch.object(tui, "switch_session") as switch:
            tui.rcon("lab:web 1")
        ssh = run.call_args_list[-1].args
        self.assertEqual(ssh[:2], ("ssh", "lab.example"))
        switch.assert_called_once_with("--create", "lab:web 1")
        with tempfile.TemporaryDirectory() as temp:
            # The remote shell receives one command line; run it here as ssh would.
            subprocess.run(["sh", "-c", ssh[2]], env={**os.environ, "XDG_STATE_HOME": temp}, check=True)
            self.assertEqual((Path(temp) / "tuios-rcon/web 1").read_text(), "web 1\n")

    def test_rcon_without_container_opens_main_and_unknown_host_fails(self):
        with patch.object(tui, "switch_session") as switch:
            tui.rcon("lab")
            tui.rcon("local")
        self.assertEqual([c.args for c in switch.call_args_list], [("--create", "lab:main"), ("--create", "main")])
        none = subprocess.CompletedProcess([], 0, json.dumps({"hosts": []}))
        with patch.object(tui, "run", return_value=none), patch.object(tui, "switch_session") as switch:
            with self.assertRaisesRegex(RuntimeError, "not in the \\[hosts\\]"):
                tui.rcon("lab:web")
        switch.assert_not_called()

    def test_space_navigation_command_passes_direction_and_client_pid(self):
        with patch.object(sys, "argv", ["tui", "space-nav", "next", "42"]), patch.object(tui, "navigate_space") as navigate:
            self.assertEqual(tui.main(), 0)
        navigate.assert_called_once_with("next", 42)

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


class RconContainerTests(unittest.TestCase):
    """The tmux rcon helpers in a TUIOS session, against fake docker/tuios/tmux."""

    def setUp(self):
        self.temp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.temp)
        self.bin = self.temp / "bin"
        self.bin.mkdir()
        self.log = self.temp / "log"
        # docker answers `exec C test -d X` only for folders under exists/.
        self.fake("docker", 'echo "docker $*" >> "$LOG"\n[ "$2 $3" = "rcon true" ] && exit 0\n[ "$3" = test ] && case "$5" in "$TEMP"/exists*) exit 0;; esac\n[ "$1" = inspect ] && { echo /work; exit 0; }\n[ "$1 $2" = "exec -it" ] && exit 0\nexit 1')
        self.fake("tmux", 'echo "tmux $*" >> "$LOG"; exit 1')
        self.fake("tuios", 'printf \'{"windows":[{"window_id":"old"},{"window_id":"used"},{"window_id":"new"}]}\'')
        self.state = self.temp / "home/.cache/tmux-pane-state-rcon"
        self.state.mkdir(parents=True)
        (self.temp / "state/tuios-rcon").mkdir(parents=True)
        (self.temp / "state/tuios-rcon/work").write_text("rcon\n")
        self.env = {key: value for key, value in os.environ.items() if not key.startswith(("TUIOS_", "TMUX"))}
        self.env.update(PATH=f"{self.bin}:/usr/bin:/bin", HOME=str(self.temp / "home"), XDG_STATE_HOME=str(self.temp / "state"), LOG=str(self.log), TEMP=str(self.temp), TUIOS_SESSION="work")

    def fake(self, name, body):
        path = self.bin / name
        path.write_text(f"#!/bin/sh\n{body}\n")
        path.chmod(0o755)

    def logged(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_pane_shell_enters_registered_container_only_for_tuios_pane_shells(self):
        shell = self.temp / "scripts/tmux-default-shell"
        shell.parent.mkdir()
        shutil.copy(ROOT / "scripts/tmux-default-shell", shell)
        (shell.parent / "tmux-docker-enter").write_text('#!/bin/sh\necho "enter $*" >> "$LOG"\n')
        (shell.parent / "tmux-docker-enter").chmod(0o755)
        (self.temp / "home/.pixi/bin").mkdir(parents=True)
        self.fake("zsh", 'echo "zsh $*" >> "$LOG"')
        (self.temp / "home/.pixi/bin/zsh").symlink_to(self.bin / "zsh")
        for extra, args in (({}, []), ({}, ["-lc", "lazygit"]), ({"TMUX": "/sock"}, []), ({"TUIOS_SESSION": "plain"}, [])):
            subprocess.run(["bash", str(shell), *args], env={**self.env, **extra}, check=True)
        self.assertEqual(self.logged(), ["enter rcon", "zsh -lc lazygit", "zsh ", "zsh "])

    def test_pane_context_reads_registration_and_the_command_entry_pane(self):
        (self.temp / "exists/sub").mkdir(parents=True)
        (self.state / "cwd-used").write_text(f"{self.temp}/exists/sub\n")
        env = {**self.env, "TUIOS_ACTIVE_PANE_ID": "used", "TUIOS_ACTIVE_PANE_CWD": "/host/only"}
        out = subprocess.run([str(ROOT / "scripts/tmux-pane-context")], env=env, capture_output=True, text=True, check=True).stdout
        self.assertIn("CONTAINER=rcon\n", out)
        self.assertIn(f"CWD={self.temp}/exists/sub\n", out)
        self.assertFalse([line for line in self.logged() if line.startswith("tmux")])
        out = subprocess.run([str(ROOT / "scripts/tmux-pane-context")], env={**env, "TUIOS_SESSION": "plain"}, capture_output=True, text=True, check=True).stdout
        self.assertIn("CONTAINER=''\nCWD=/host/only\n", out)

    def test_new_pane_takes_cwd_of_the_session_pane_that_prompted_last(self):
        for name, age in (("old", 30), ("used", 10), ("new", 0), ("other-session", 0)):
            path = self.state / f"cwd-{name}"
            path.write_text(f"{self.temp}/exists/{name}\n")
            os.utime(path, (time.time() - age, time.time() - age))
        env = {**self.env, "TUIOS_PANE_ID": "new"}
        subprocess.run([str(ROOT / "scripts/tmux-docker-enter"), "rcon"], env=env, cwd=self.temp, check=True)
        exec_line = self.logged()[-1]
        self.assertIn(f"-w {self.temp}/exists/used rcon zsh", exec_line)
        self.assertIn("-e RCON_PANE_ID=new", exec_line)


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
        for key, action in {"h": "prev_session", "l": "next_session"}.items():
            self.assertEqual(bindings["global", f"ctrl+alt+{key}"], action)
            self.assertEqual(bindings["global", f"alt+{key}"], action)
        self.assertEqual(bindings["global", "ctrl+alt+j"], "command:next-space")
        self.assertEqual(bindings["global", "ctrl+alt+k"], "command:previous-space")
        for key in ("alt+j", "alt+k", "ctrl+p"):
            self.assertNotIn(("global", key), bindings)
        self.assertEqual(bindings["prefix", "s"], "prefix_session_switcher")
        self.assertEqual(bindings["prefix", "tab"], "last_session")
        self.assertEqual(bindings["prefix", "esc"], "command:prefix-escape-noop")
        self.assertEqual(bindings["prefix", "x"], "command:kill-pane")
        self.assertEqual(bindings["prefix", "X"], "command:kill-workspace")
        for key in ("w", "x"):
            self.assertNotEqual(bindings.get(("window", key)), "close_window")
        self.assertEqual(bindings["window", "s"], "focus_sidebar")
        self.assertEqual(bindings["prefix", "ctrl+s"], "command:session-space")
        self.assertNotIn(("prefix", "ctrl+g"), bindings)

    def test_restore_project_trust_and_remote_action_placement(self):
        config = tomllib.loads((ROOT / "common/tuios/.config/tuios/config.d/dotfiles.toml").read_text())
        self.assertEqual(config["daemon"]["resume_agents"], "ask")
        self.assertEqual(config["tape"]["autorun"], "ask")
        self.assertEqual(config["appearance"]["auto_enter_terminal_on_focus"], "off")
        for entry in config["keybindings"]["command"]:
            self.assertNotIn("tui nav ", entry.get("command", ""))
            if entry["key"] in [f"{modifier}{key}" for modifier in ("alt+", "ctrl+alt+") for key in "hjkl"]:
                self.assertEqual(entry["type"], "shell", entry["name"])
            if entry["name"] in ("project-root", "projects", "session-space"):
                self.assertEqual(entry["type"], "popup", entry["name"])
        space = next(entry for entry in config["keybindings"]["command"] if entry["name"] == "session-space")
        self.assertIn("scripts/tui space'", space["command"])
        for name, direction in (("next-space", "next"), ("previous-space", "prev")):
            command = next(entry for entry in config["keybindings"]["command"] if entry["name"] == name)
            self.assertEqual(command["type"], "shell")
            self.assertIn("client_pid=$PPID;", command["command"])
            self.assertIn(f"space-nav {direction} $client_pid", command["command"])
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
