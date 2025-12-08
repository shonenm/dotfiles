-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local map = vim.api.nvim_set_keymap
local opts = { noremap = true, silent = true }
-- move window
map("n", "<Leader>j", "<C-w>j", { noremap = true, silent = true })
map("n", "<Leader>k", "<C-w>k", { noremap = true, silent = true })
map("n", "<Leader>l", "<C-w>l", { noremap = true, silent = true })
map("n", "<Leader>h", "<C-w>h", { noremap = true, silent = true })

-- split window
map("n", "<Leader>s", ":sp\n", { noremap = true })
map("n", "<Leader>v", ":vs\n", { noremap = true })

-- close window
map("n", "<Leader>w", ":w\n", { noremap = true })
map("n", "<Leader>q", ":q\n", { noremap = true })
map("n", "<Leader>wq", ":wq\n", { noremap = true })

-- open terminal
map("n", "<Leader>tt", ":terminal\n", { noremap = true })

-- buffer (tabline) navigation with Ctrl-h/l
map("n", "<C-h>", "<cmd>bprevious<CR>", opts)
map("n", "<C-l>", "<cmd>bnext<CR>", opts)

-- show diagnostics
map("n", "<Leader>d", ":lua vim.diagnostic.open_float()<CR>", { noremap = true })

-- rebind embeded command
map("n", "<C-_>", "gcc", { noremap = false })
map("v", "<C-_>", "gc", { noremap = false })

-- quick open LazyVim plugin
map("n", "<Leader>p", ":Lazy\n", { noremap = true })
