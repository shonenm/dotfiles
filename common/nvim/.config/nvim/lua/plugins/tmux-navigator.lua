local in_tuios = vim.env.TUIOS_ENV == "1"

local function tuios_report(verb, value)
  io.stdout:write("\027]7777;tuios-nvim-navigator;" .. verb .. ";" .. value .. "\007")
  io.stdout:flush()
end

local function navigate(key, direction, command)
  if not in_tuios then
    vim.cmd(command)
    return
  end
  local window = vim.api.nvim_get_current_win()
  local explorer = vim.bo.filetype == "snacks_picker_list"
  if not explorer then
    vim.cmd("wincmd " .. key)
  end
  if explorer or vim.api.nvim_get_current_win() == window then
    tuios_report("focus", direction)
  end
end

return {
  "christoomey/vim-tmux-navigator",
  lazy = false,  -- 常にロード（tmux検出に必要）
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
              if in_tuios then tuios_report("focus", "left") else vim.fn.system("tmux select-pane -L") end
            end, { buffer = true })
            vim.keymap.set("n", "<C-j>", function()
              if in_tuios then tuios_report("focus", "down") else vim.fn.system("tmux select-pane -D") end
            end, { buffer = true })
            vim.keymap.set("n", "<C-k>", function()
              if in_tuios then tuios_report("focus", "up") else vim.fn.system("tmux select-pane -U") end
            end, { buffer = true })
          end)
        end
      end,
    })
  end,
}
