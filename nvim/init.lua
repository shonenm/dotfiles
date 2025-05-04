-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end

vim.opt.rtp:prepend(lazypath)
vim.opt.wrap = true

require("lazy").setup({
  spec = {
    { "nvim-lualine/lualine.nvim" }, -- 軽い UI系（正常起動だけ確認用）
  },
})