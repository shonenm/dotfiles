-- merge-review: 3way diff (ours | resolved | theirs) 用キーマップ・UI
-- merge-review コマンドで nvim がタブ付きで起動された時に自動設定される

local setup_done = {}
local hunk_cache = {} -- tabpage → { hunks, resolved_win }
local pending_timer = nil

local function cancel_pending()
  if pending_timer then
    vim.fn.timer_stop(pending_timer)
    pending_timer = nil
  end
end

-- diff hunk の位置リストを取得 (行番号の昇順)
-- 呼び出し元が resolved ペインにフォーカスしていること
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

-- hunk カウントを実行して winbar とキャッシュを更新
local function update_hunk_count(tabpage, resolved_win)
  local hunks = get_diff_hunks()
  hunk_cache[tabpage] = hunks
  pcall(function()
    vim.wo[resolved_win].winbar = " RESOLVED (" .. #hunks .. " hunks)"
  end)
  return hunks
end

-- キャッシュ済みの hunk リストを返す。なければオンデマンドで計算
local function get_hunks_cached(tabpage, resolved_win)
  if hunk_cache[tabpage] then return hunk_cache[tabpage] end
  return update_hunk_count(tabpage, resolved_win)
end

local function setup_merge_review(bufs)
  local tabpage = vim.api.nvim_get_current_tabpage()

  -- diff が未有効なら有効化
  if not vim.wo[bufs[1].win].diff then
    for _, b in ipairs(bufs) do
      vim.api.nvim_set_current_win(b.win)
      vim.cmd("diffthis")
    end
    -- 3ウィンドウの diff 確定後にスクロール位置を同期
    vim.cmd("syncbind")
  end

  -- scrolloff を無効化 (filler line 非対称による scrollbind ずれ防止)
  for _, b in ipairs(bufs) do
    vim.wo[b.win].scrolloff = 0
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

  -- winbar: ラベルのみ (hunk 数は非同期で後から更新)
  vim.wo[bufs[1].win].winbar = " OURS"
  vim.wo[bufs[2].win].winbar = " RESOLVED"
  vim.wo[bufs[3].win].winbar = " THEIRS"

  -- resolved にフォーカス
  vim.api.nvim_set_current_win(bufs[2].win)

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
  local resolved_win = bufs[2].win
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
    hunk_cache[tabpage] = nil
    update_hunk_count(tabpage, resolved_win)
  end, vim.tbl_extend("force", ropts, { desc = "Update diff + hunk count" }))

  -- hunk 番号ジャンプ (1-9, オンデマンド計算)
  for i = 1, 9 do
    vim.keymap.set("n", "<leader>m" .. i, function()
      local h = get_hunks_cached(tabpage, resolved_win)
      if i > #h then
        vim.notify("Hunk " .. i .. "/" .. #h, vim.log.levels.WARN)
        return
      end
      vim.api.nvim_win_set_cursor(0, { h[i], 0 })
      vim.cmd("normal! zz")
    end, vim.tbl_extend("force", ropts, { desc = "Jump to hunk " .. i }))
  end

  -- nomodifiable 設定 (ours/theirs)
  vim.bo[bufs[1].buf].modifiable = false
  vim.bo[bufs[3].buf].modifiable = false

  setup_done[tabpage] = true

  -- 非同期 hunk カウント: 100ms 後にまだ同じタブなら計算
  cancel_pending()
  pending_timer = vim.fn.timer_start(100, function()
    vim.schedule(function()
      pending_timer = nil
      if vim.api.nvim_get_current_tabpage() ~= tabpage then return end
      if hunk_cache[tabpage] then return end
      update_hunk_count(tabpage, resolved_win)
    end)
  end)
end

local function try_setup()
  cancel_pending()

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
