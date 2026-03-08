-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

-- Window navigation: vim-tmux-navigator が担当 (C-h/j/k/l)

-- Save & Quit
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
map("n", "<leader>wq", "<cmd>wq<cr>", { desc = "Save and Quit" })

-- Split windows
map("n", "<leader>sv", "<cmd>vsplit<cr>", { desc = "Vertical split" })
map("n", "<leader>sh", "<cmd>split<cr>", { desc = "Horizontal split" })

-- Better escape
map("i", "jk", "<Esc>", { desc = "Escape" })

-- Move lines
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

map("n", "n", "nzzzv", { desc = "Next search result" })
map("n", "N", "Nzzzv", { desc = "Previous search result" })

-- Clear search highlight
map("n", "<Esc>", "<cmd>noh<cr>", { desc = "Clear search highlight" })

-- Emacs-style keybindings in Insert mode (macOS compatible)
map("i", "<C-a>", "<Home>", { desc = "Beginning of line" })
map("i", "<C-e>", "<End>", { desc = "End of line" })
map("i", "<C-f>", "<Right>", { desc = "Forward char" })
map("i", "<C-b>", "<Left>", { desc = "Backward char" })
map("i", "<C-p>", "<Up>", { desc = "Previous line" })
map("i", "<C-n>", "<Down>", { desc = "Next line" })
map("i", "<C-d>", "<Del>", { desc = "Delete char" })
map("i", "<C-k>", "<C-o>D", { desc = "Kill to end of line" })

-- Horizontal scroll (nowrap時に有効、差分ビュー等で使用)
-- scrollbind時は現ウィンドウをスクロール後、他のscrollbindウィンドウにleftcolを同期
local function scroll_horizontal(cmd)
  vim.cmd("normal! " .. cmd)
  local cur_win = vim.api.nvim_get_current_win()
  if not vim.wo[cur_win].scrollbind then
    return
  end
  local leftcol = vim.fn.winsaveview().leftcol
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= cur_win and vim.wo[w].scrollbind then
      vim.api.nvim_win_call(w, function()
        vim.fn.winrestview({ leftcol = leftcol })
      end)
    end
  end
end
map("n", "<C-S-u>", function()
  scroll_horizontal("zH")
end, { desc = "Scroll half screen left" })
map("n", "<C-S-d>", function()
  scroll_horizontal("zL")
end, { desc = "Scroll half screen right" })
