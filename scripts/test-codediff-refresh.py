#!/usr/bin/env python3
"""CodeDiff local patch: unchanged notifications stay quiet; real inputs refresh.

Requires nvim and the installed codediff.nvim/nui.nvim plugins. Does not load
Lazy.nvim or write its lockfile. All Git/file mutations stay in a temporary repo.
"""

import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DATA = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim/lazy"

LUA = r'''
vim.opt.rtp:prepend(vim.env.TEST_PLUGIN_DATA .. "/nui.nvim")
vim.opt.rtp:prepend(vim.env.TEST_PLUGIN_DATA .. "/codediff.nvim")
vim.o.autoread = true
vim.api.nvim_create_augroup("snacks.explorer", {})
dofile(vim.env.TEST_CODEDIFF_CONFIG).setup({explorer = {auto_refresh = false}})
vim.cmd("runtime plugin/codediff.lua")

local lc = require("codediff.ui.lifecycle")
local tree = require("codediff.ui.lib.tree")
local renders, render = 0, tree.render
tree.render = function(self, ...)
  renders = renders + 1
  return render(self, ...)
end
local function wait_for(predicate, message)
  assert(vim.wait(3000, predicate, 10), message)
end
local function settle()
  vim.wait(300, function() return false end, 10)
end
local function git(...)
  local result = vim.system({"git", ...}, {text = true}):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local function write(text)
  vim.fn.writefile({text, "line2", "line3", "line4", "line5"}, "file.txt")
end
local function first_line(buf)
  return buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
end
local function test()
  local mode = vim.env.TEST_MODE
  local commands = {
    immutable = "CodeDiff --inline HEAD~1...HEAD",
    working = "CodeDiff HEAD~1",
    staged = "CodeDiff",
    head = "CodeDiff",
  }
  vim.cmd(commands[mode])
  wait_for(function() return lc.get_panel_view(vim.api.nvim_get_current_tabpage()) ~= nil end, "explorer did not open")
  local tab = vim.api.nvim_get_current_tabpage()
  local explorer = lc.get_panel_view(tab)
  local group = mode == "staged" and "staged" or "unstaged"
  local file = assert(explorer.status_result[group][1], "file missing")
  local selection = vim.tbl_extend("force", file, {group = group, git_root = explorer.git_root})
  explorer.on_file_select(selection)
  explorer.on_file_select(selection)
  local expected = mode == "staged" and "stage" or mode == "head" and "local" or "first"
  wait_for(function()
    local session = lc.get_session(tab)
    return session and first_line(session.modified_bufnr) == expected
  end, "initial content missing")
  settle()

  local function refresh(force)
    local done = false
    explorer._request_refresh(force, function() done = true end)
    wait_for(function() return done end, "scheduler did not complete")
    settle()
  end
  refresh(true) -- Initialize the hunk-count cache before measuring idle refreshes.
  local session = lc.get_session(tab)
  local win = session.modified_win
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, {3, 0})
  local function assert_position()
    assert(vim.api.nvim_get_current_win() == win, "refresh stole focus")
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(win), {3, 0}), "refresh moved cursor")
  end
  local before = renders
  for i = 1, 3 do
    vim.fn.writefile({tostring(i)}, "unrelated.log")
    refresh(true) -- Native watcher invalidation, even though the viewed input is unchanged.
  end
  refresh(false) -- Polling fallback must also stay quiet.
  assert(renders == before, "unchanged input was rendered again")
  assert_position()

  if mode == "immutable" then
    write("other")
    git("add", "file.txt")
    refresh(true) -- Index/worktree cannot change the two pinned commit inputs.
    assert(renders == before, "immutable diff reacted to index/worktree")
    assert(first_line(lc.get_session(tab).modified_bufnr) == "first")
  else
    local old_status = vim.deepcopy(explorer.status_result)
    if mode == "head" then
      write("second")
      git("add", "file.txt")
      git("-c", "core.hooksPath=/dev/null", "commit", "-qm", "external commit")
      write("local")
    else
      write("other")
      if mode == "staged" then git("add", "file.txt") end
    end
    refresh(true)
    session = lc.get_session(tab)
    local actual = mode == "head" and session.original_bufnr or session.modified_bufnr
    assert(first_line(actual) == (mode == "head" and "second" or "other"), "real input stayed stale")
    if mode == "head" then
      assert(session.original_revision == git("rev-parse", "HEAD"), "HEAD resolution stayed cached")
    end
    assert(vim.deep_equal(old_status, explorer.status_result), "fixture must retain identical status/line stats")
    assert_position()
    if mode == "working" then
      vim.bo[session.modified_bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(session.modified_bufnr, 0, 1, false, {"unsaved"})
      write("disk")
      refresh(true)
      assert(first_line(session.modified_bufnr) == "unsaved", "unsaved edit was overwritten")
      assert(vim.bo[session.modified_bufnr].modified, "unsaved flag was lost")
    end
  end
  print("PASS " .. mode)
end
vim.schedule(function()
  local ok, err = xpcall(test, debug.traceback)
  if not ok then vim.api.nvim_err_writeln(err) end
  vim.cmd(ok and "qa!" or "cquit 1")
end)
'''


def main():
    for plugin in ("codediff.nvim", "nui.nvim"):
        if not (DATA / plugin).is_dir():
            raise SystemExit(f"Missing installed plugin: {DATA / plugin}")
    with tempfile.TemporaryDirectory(prefix="codediff-refresh-") as tmp:
        tmp = Path(tmp)
        script = tmp / "test.lua"
        script.write_text(LUA)
        for mode in ("immutable", "working", "staged", "head"):
            repo = tmp / mode
            repo.mkdir()

            def git(*args):
                subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)

            def write(text):
                (repo / "file.txt").write_text(text + "\nline2\nline3\nline4\nline5\n")

            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("config", "commit.gpgsign", "false")
            for text in ("old", "first"):
                write(text)
                git("add", "file.txt")
                git("-c", "core.hooksPath=/dev/null", "commit", "-qm", text)
            if mode == "staged":
                write("stage")
                git("add", "file.txt")
            if mode == "head":
                write("local")
            (repo / "unrelated.log").write_text("initial\n")
            env = dict(os.environ, TEST_MODE=mode, TEST_PLUGIN_DATA=str(DATA),
                       TEST_CODEDIFF_CONFIG=str(ROOT / "common/nvim/.config/nvim/lua/config/codediff.lua"),
                       LIVE_PR_REVIEW="1", LIVE_PR_REVIEWED_FILE=str(tmp / "reviewed.json"))
            subprocess.run(["nvim", "--headless", "-u", "NONE", "-i", "NONE",
                            "+luafile " + str(script)], cwd=repo, env=env, check=True, timeout=20)


if __name__ == "__main__":
    main()
