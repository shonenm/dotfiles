local in_tuios = vim.env.TUIOS_ENV == "1"
-- Rex 側の binding は common/rex/.config/rex/init.lua の Ctrl+h/j/k/l。
local in_rex = not in_tuios and (vim.env.REX_SESSION or "") ~= ""

local function tuios_report(verb, value)
  io.stdout:write("\027]7777;tuios-nvim-navigator;" .. verb .. ";" .. value .. "\007")
  io.stdout:flush()
end

local function outer_focus(direction)
  if in_tuios then
    tuios_report("focus", direction)
  else
    -- server の rex focus ではなく app の pane.focus で動かす。app が覚える focus を更新するため。
    vim.system({ "rex", "do", "pane.focus", "direction=" .. direction })
  end
end

local function navigate(key, direction, command)
  if not in_tuios and not in_rex then
    vim.cmd(command)
    return
  end
  local window = vim.api.nvim_get_current_win()
  vim.cmd("wincmd " .. key)
  if vim.api.nvim_get_current_win() == window then
    outer_focus(direction)
  end
end

return {
  "christoomey/vim-tmux-navigator",
  lazy = false,  -- 常にロード（tmux検出に必要）
  -- plugin 既定の <C-hjkl> が keys の navigate() を上書きしないようにする。
  init = function() vim.g.tmux_navigator_no_mappings = 1 end,
  keys = {
    { "<C-h>", function() navigate("h", "left", "TmuxNavigateLeft") end, desc = "Navigate Left" },
    { "<C-j>", function() navigate("j", "down", "TmuxNavigateDown") end, desc = "Navigate Down" },
    { "<C-k>", function() navigate("k", "up", "TmuxNavigateUp") end, desc = "Navigate Up" },
    { "<C-l>", function() navigate("l", "right", "TmuxNavigateRight") end, desc = "Navigate Right" },
  },
  config = function()
    if in_tuios then
      local group = vim.api.nvim_create_augroup("TuiosNavigator", { clear = true })
      vim.api.nvim_create_autocmd({ "VimEnter", "VimResume", "FocusGained" }, {
        group = group,
        callback = function() tuios_report("state", "active") end,
      })
      vim.api.nvim_create_autocmd({ "VimSuspend", "VimLeavePre" }, {
        group = group,
        callback = function() tuios_report("state", "inactive") end,
      })
      vim.schedule(function() tuios_report("state", "active") end)
    end
    -- snacks explorer で C-hjk が正しく動作するよう修正
    -- BufEnter + vim.schedule で snacks のキーマップ設定後に上書き
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*",
      callback = function()
        if vim.bo.filetype == "snacks_picker_list" then
          vim.schedule(function()
            vim.keymap.set("n", "<C-h>", function()
              if in_tuios or in_rex then outer_focus("left") else vim.fn.system("tmux select-pane -L") end
            end, { buffer = true })
            vim.keymap.set("n", "<C-j>", function()
              if in_tuios or in_rex then outer_focus("down") else vim.fn.system("tmux select-pane -D") end
            end, { buffer = true })
            vim.keymap.set("n", "<C-k>", function()
              if in_tuios or in_rex then outer_focus("up") else vim.fn.system("tmux select-pane -U") end
            end, { buffer = true })
          end)
        end
      end,
    })
  end,
}
