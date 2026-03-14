-- merge-review: 3way diff (ours | resolved | theirs) 用キーマップ・UI
-- merge-review コマンドで nvim がタブ付きで起動された時に自動設定される

local setup_done = {}

-- diff hunk の位置リストを取得 (行番号の昇順)
local function get_diff_hunks()
  if not vim.wo.diff then return {} end
  local saved = vim.fn.winsaveview()
  local hunks = {}
  vim.cmd("keepjumps normal! G")
  local last_line = vim.api.nvim_buf_line_count(0) + 1
  while true do
    local ok = pcall(function() vim.cmd("keepjumps normal! [c") end)
    if not ok then break end
    local line = vim.api.nvim_win_get_cursor(0)[1]
    if line >= last_line then break end
    last_line = line
    table.insert(hunks, 1, line)
  end
  vim.fn.winrestview(saved)
  return hunks
end

local function setup_merge_review(bufs)
  local tabpage = vim.api.nvim_get_current_tabpage()

  -- diff が未有効なら有効化
  if not vim.wo[bufs[1].win].diff then
    for _, b in ipairs(bufs) do
      vim.api.nvim_set_current_win(b.win)
      vim.cmd("diffthis")
    end
  end

  -- filetype が未設定なら resolved のパスから推定して設定
  local ft = vim.filetype.match({ filename = bufs[2].name })
  if ft then
    for _, b in ipairs(bufs) do
      if vim.bo[b.buf].filetype == "" then
        vim.bo[b.buf].filetype = ft
      end
    end
  end

  -- hunk 数を取得 (resolved ペインで計測)
  vim.api.nvim_set_current_win(bufs[2].win)
  local hunks = get_diff_hunks()

  -- winbar: ラベルと hunk 数
  vim.wo[bufs[1].win].winbar = " OURS"
  vim.wo[bufs[2].win].winbar = " RESOLVED (" .. #hunks .. " hunks)"
  vim.wo[bufs[3].win].winbar = " THEIRS"

  -- 全ペイン共通キーマップ
  for _, b in ipairs(bufs) do
    local opts = { buffer = b.buf, noremap = true, silent = true }
    -- H/L → タブ移動 (LazyVim の bnext/bprevious をオーバーライド)
    vim.keymap.set("n", "H", "<cmd>tabprevious<CR>",
      vim.tbl_extend("force", opts, { desc = "Prev file" }))
    vim.keymap.set("n", "L", "<cmd>tabnext<CR>",
      vim.tbl_extend("force", opts, { desc = "Next file" }))
  end

  -- resolved ペイン専用キーマップ
  local resolved_buf = bufs[2].buf
  local ropts = { buffer = resolved_buf, noremap = true, silent = true }

  vim.keymap.set("n", "<leader>mo", function()
    vim.cmd("diffget " .. bufs[1].buf)
  end, vim.tbl_extend("force", ropts, { desc = "Get from ours (left)" }))

  vim.keymap.set("n", "<leader>mt", function()
    vim.cmd("diffget " .. bufs[3].buf)
  end, vim.tbl_extend("force", ropts, { desc = "Get from theirs (right)" }))

  vim.keymap.set("n", "<leader>mu", function()
    vim.cmd("diffupdate")
    -- hunk 数を再計算して winbar 更新
    local new_hunks = get_diff_hunks()
    vim.wo[bufs[2].win].winbar = " RESOLVED (" .. #new_hunks .. " hunks)"
  end, vim.tbl_extend("force", ropts, { desc = "Update diff" }))

  -- hunk 番号ジャンプ (1-9)
  for i = 1, 9 do
    vim.keymap.set("n", "<leader>m" .. i, function()
      local h = get_diff_hunks()
      if i > #h then
        vim.notify("Hunk " .. i .. "/" .. #h, vim.log.levels.WARN)
        return
      end
      vim.api.nvim_win_set_cursor(0, { h[i], 0 })
      vim.cmd("normal! zz")
    end, vim.tbl_extend("force", ropts, { desc = "Jump to hunk " .. i }))
  end

  -- nomodifiable 設定 (ours/theirs)
  vim.wo[bufs[1].win].modifiable = false
  vim.wo[bufs[3].win].modifiable = false

  -- resolved にフォーカス
  vim.api.nvim_set_current_win(bufs[2].win)

  setup_done[tabpage] = true
end

local function try_setup()
  local tabpage = vim.api.nvim_get_current_tabpage()
  if setup_done[tabpage] then return end

  local wins = vim.api.nvim_tabpage_list_wins(tabpage)
  if #wins ~= 3 then return end

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

  setup_merge_review(bufs)
end

vim.api.nvim_create_autocmd({ "VimEnter", "TabEnter" }, {
  callback = function()
    vim.schedule(try_setup)
  end,
})

return {}
