return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  config = function() 
    require('nvim-treesitter.configs').setup({
      ensure_installed = {
          "ruby",
          "go",
          "zig",
          "tsx",
          "javascript",
          "typescript",
          "json",
          "yaml",
          "html",
          "css",
          "lua",
          "vim",
          "markdown",
          "sql",
          "yaml"
      },
      sync_install = false,
      highlight = { enable = true },
      indent = { enable = true },
    })
  end
}
