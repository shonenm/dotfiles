-- .env file support (syntax highlighting via treesitter)
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = { "dotenv" },
    },
  },
  -- Set filetype for .env files
  {
    "LazyVim/LazyVim",
    opts = function()
      vim.filetype.add({
        filename = {
          [".env"] = "dotenv",
          [".env.local"] = "dotenv",
          [".env.development"] = "dotenv",
          [".env.production"] = "dotenv",
          [".env.staging"] = "dotenv",
          [".env.e2e"] = "dotenv",
          [".env.test"] = "dotenv",
        },
        pattern = {
          ["%.env%.[%w_.-]+"] = "dotenv",
        },
      })
    end,
  },
}
