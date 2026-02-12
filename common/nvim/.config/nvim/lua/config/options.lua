-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Clipboard
vim.opt.clipboard = "unnamedplus"

-- Line numbers
vim.opt.relativenumber = true

-- Indentation
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- UI
vim.opt.termguicolors = true
vim.opt.cursorline = true
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.wrap = true

-- C-u/C-d scroll 1/4 of window height (updated dynamically)
local function update_scroll()
  local height = vim.api.nvim_win_get_height(0)
  vim.wo.scroll = math.max(1, math.floor(height / 4))
end
vim.api.nvim_create_autocmd({ "WinEnter", "WinResized" }, {
  callback = update_scroll,
})
update_scroll()

-- Cursor visibility (mode-specific cursor shape)
vim.opt.guicursor = table.concat({
  "n-c:block-Cursor/lCursor",
  "i-ci-ve:ver25-iCursor/lCursor",
  "v:block-vCursor/lCursor",
  "r-cr:hor20-rCursor/lCursor",
  "o:hor50-Cursor/lCursor",
  "a:blinkwait700-blinkoff400-blinkon250",
}, ",")

-- Disable swap files
vim.opt.swapfile = false

-- Undo persistence (XDG準拠)
local undodir = vim.fn.stdpath("state") .. "/undo"
if vim.fn.isdirectory(undodir) == 0 then
  vim.fn.mkdir(undodir, "p")
end
vim.opt.undodir = undodir
vim.opt.undofile = true
vim.opt.undolevels = 10000
vim.opt.undoreload = 10000

-- Auto reload files changed outside of Neovim
vim.opt.autoread = true

-- Folding
vim.opt.foldcolumn = "1"
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldenable = true
