-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end

local opt = vim.opt
local api = vim.api

opt.rtp:prepend(lazypath)
opt.wrap = true
api.nvim_set_keymap("n", "gj", "gj<SID>g", { noremap = false })
api.nvim_set_keymap("n", "gk", "gk<SID>g", { noremap = false })
api.nvim_set_keymap("n", "<SID>gj", "gj<SID>g", { noremap = true, silent = true })
api.nvim_set_keymap("n", "<SID>gk", "gk<SID>g", { noremap = true, silent = true })
api.nvim_set_keymap("n", "<SID>g", "<Nop>", { noremap = false })

require("lazy").setup("plugins", {
  ui = {
    icons = {
      cmd = "⌘",
      config = "🛠",
      event = "📅",
      ft = "📂",
      init = "⚙",
      keys = "🗝",
      plugin = "🔌",
      runtime = "💻",
      require = "🌙",
      source = "📄",
      start = "🚀",
      task = "📌",
      lazy = "💤 ",
    },
  },
  checker = {
    enabled = true, -- プラグインのアップデートを自動的にチェック
  },
  diff = {
    cmd = "delta",
  },
  rtp = {
    disabled_plugins = {
      "gzip",
      "matchit",
      "matchparen",
      "netrwPlugin",
      "tarPlugin",
      "tohtml",
      "tutor",
      "zipPlugin",
    },
  },
  spec = {
    { "akinsho/bufferline.nvim", enabled = false },
  },
})
