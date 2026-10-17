#!/usr/bin/env python3
"""External commits must update the open CodeDiff without stealing focus.

Uses the installed codediff.nvim/nui.nvim plugins and -u NONE. Does not load
Lazy.nvim or write its lockfile. Git mutations stay in a temporary repo.
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
vim.api.nvim_create_augroup("snacks.explorer", {})
local specs = dofile(vim.env.TEST_CODEDIFF_PLUGIN)
local opts = specs[2].opts
assert(opts.explorer.line_stats.enabled, "line statistics disabled in plugin config")
opts.explorer.auto_refresh = false
dofile(vim.env.TEST_CODEDIFF_CONFIG).setup(opts)
vim.cmd("runtime plugin/codediff.lua")

local lc = require("codediff.ui.lifecycle")
local function wait_for(predicate, message)
  assert(vim.wait(3000, predicate, 10), message)
end
local function settle()
  vim.wait(400, function() return false end, 10)
end
local function git(...)
  local result = vim.system({"git", ...}, {text = true}):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local function first_line(buf)
  return buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
end

local function test()
  local nodes = require("codediff.ui.explorer.nodes")
  local Tree = require("codediff.ui.lib.tree")
  local config = require("codediff.config")
  local node = Tree.Node({text = "file.txt", data = {
    path = "file.txt", group = "unstaged", status_symbol = "M",
    line_stats = {insertions = 12, deletions = 4},
  }})
  for _, selected_path in ipairs({"", "file.txt"}) do
    local row = nodes.prepare_node(node, 40, selected_path, "unstaged"):content()
    assert(row:find("+12 -4", 1, true), "file counts missing: " .. row)
    assert(vim.fn.strdisplaywidth(row) == 40, "stats overflow explorer width")
  end
  node.data.line_stats = {binary = true}
  assert(nodes.prepare_node(node, 40):content():find("bin", 1, true), "binary label missing")
  config.options.explorer.line_stats.enabled = false
  assert(not nodes.prepare_node(node, 40):content():find("bin", 1, true), "disabled stats still shown")
  config.options.explorer.line_stats.enabled = true

  vim.cmd("CodeDiff --inline HEAD~1")
  wait_for(function() return lc.get_explorer(vim.api.nvim_get_current_tabpage()) ~= nil end, "explorer did not open")
  local tab = vim.api.nvim_get_current_tabpage()
  local explorer = lc.get_explorer(tab)
  wait_for(function()
    local rows = table.concat(vim.api.nvim_buf_get_lines(explorer.bufnr, 0, -1, false), "\n")
    return rows:find("+1 -1", 1, true) and rows:find("Files (1 · +1 -1)", 1, true)
      and rows:find("○", 1, true)
  end, "Git line counts missing from explorer")
  local file = assert(explorer.status_result.unstaged[1], "file missing")
  explorer.on_file_select(vim.tbl_extend("force", file, {group = "unstaged", git_root = explorer.git_root}))
  wait_for(function()
    local session = lc.get_session(tab)
    return session and first_line(session.modified_bufnr) == "first"
  end, "initial content missing")
  settle()

  local session = lc.get_session(tab)
  local win = session.modified_win
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, {3, 0})
  local function refresh()
    require("codediff.ui.explorer.refresh").refresh(explorer)
    settle()
  end
  refresh() -- record resolved SHAs without treating the first poll as a move
  assert(first_line(lc.get_session(tab).modified_bufnr) == "first")
  assert(vim.api.nvim_get_current_win() == win, "idle refresh stole focus")
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(win), {3, 0}), "idle refresh moved cursor")

  local Tree = require("codediff.ui.lib.tree")
  local renders, orig_render = 0, Tree.render
  Tree.render = function(self, ...)
    renders = renders + 1
    return orig_render(self, ...)
  end
  local selects = 0
  local orig_select = explorer.on_file_select
  explorer.on_file_select = function(file, opts)
    selects = selects + 1
    return orig_select(file, opts)
  end
  vim.fn.writefile({"noise"}, "unrelated.log")
  refresh()
  refresh()
  assert(renders == 0, "idle refresh re-rendered the tree")
  assert(selects == 0, "idle refresh re-selected the open file")
  assert(first_line(lc.get_session(tab).modified_bufnr) == "first", "unrelated write changed the open diff")
  assert(vim.api.nvim_get_current_win() == win, "unrelated write stole focus")
  explorer.on_file_select = orig_select
  Tree.render = orig_render

  vim.fn.writefile({"second", "line2", "line3", "line4", "line5"}, "file.txt")
  git("add", "file.txt")
  git("-c", "core.hooksPath=/dev/null", "commit", "-qm", "external commit")
  refresh()
  wait_for(function()
    return first_line(lc.get_session(tab).modified_bufnr) == "second"
  end, "external commit left the open diff stale")
  assert(vim.api.nvim_get_current_win() == win, "commit refresh stole focus")
  print("PASS")
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
        repo = tmp / "repo"
        repo.mkdir()

        def git(*args):
            subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)

        git("init", "-q")
        git("config", "user.name", "Test")
        git("config", "user.email", "test@example.com")
        git("config", "commit.gpgsign", "false")
        for text in ("old", "first"):
            (repo / "file.txt").write_text(text + "\nline2\nline3\nline4\nline5\n")
            git("add", "file.txt")
            git("-c", "core.hooksPath=/dev/null", "commit", "-qm", text)
        env = dict(
            os.environ,
            TEST_PLUGIN_DATA=str(DATA),
            TEST_CODEDIFF_CONFIG=str(ROOT / "common/nvim/.config/nvim/lua/config/codediff.lua"),
            TEST_CODEDIFF_PLUGIN=str(ROOT / "common/nvim/.config/nvim/lua/plugins/codediff.lua"),
            LIVE_PR_REVIEW="1",
            LIVE_PR_REVIEWED_FILE=str(tmp / "reviewed.json"),
        )
        subprocess.run(
            ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "+luafile " + str(script)],
            cwd=repo,
            env=env,
            check=True,
            timeout=20,
        )


if __name__ == "__main__":
    main()
