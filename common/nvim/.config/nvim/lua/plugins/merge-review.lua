-- merge-review: 3way diff (ours | resolved | theirs) 用キーマップ
-- merge-review コマンドで nvim がタブ付きで起動された時に自動設定される

local setup_done = {} -- タブごとの設定済みフラグ

local function setup_merge_review_keymaps()
  local tabpage = vim.api.nvim_get_current_tabpage()
  if setup_done[tabpage] then return end

  local wins = vim.api.nvim_tabpage_list_wins(tabpage)
  if #wins ~= 3 then return end

  -- 3ペイン全てが diff モードか確認
  for _, win in ipairs(wins) do
    if not vim.wo[win].diff then return end
  end

  -- バッファ名から merge-review パターンを検出
  local bufs = {}
  for _, win in ipairs(wins) do
    bufs[#bufs + 1] = {
      win = win,
      buf = vim.api.nvim_win_get_buf(win),
      name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)),
    }
  end

  if not bufs[1].name:match("%.ours$") or not bufs[3].name:match("%.theirs$") then
    return
  end

  -- 中央ペイン (resolved) にキーマップを設定
  local resolved_buf = bufs[2].buf
  local opts = { buffer = resolved_buf, noremap = true, silent = true }

  vim.keymap.set("n", "<leader>mo", function()
    vim.cmd("diffget " .. bufs[1].buf)
  end, vim.tbl_extend("force", opts, { desc = "Get from ours (left)" }))

  vim.keymap.set("n", "<leader>mt", function()
    vim.cmd("diffget " .. bufs[3].buf)
  end, vim.tbl_extend("force", opts, { desc = "Get from theirs (right)" }))

  vim.keymap.set("n", "<leader>mu", "<cmd>diffupdate<CR>",
    vim.tbl_extend("force", opts, { desc = "Update diff" }))

  setup_done[tabpage] = true
end

vim.api.nvim_create_autocmd({ "VimEnter", "TabEnter" }, {
  callback = function()
    vim.schedule(setup_merge_review_keymaps)
  end,
})

return {}
