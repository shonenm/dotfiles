return {
  -- Treesitter: Solidity syntax highlighting
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = { "solidity" },
    },
  },

  -- LSP: Nomic Foundation Solidity Language Server
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        solidity_ls_nomicfoundation = {},
      },
    },
  },

  -- Mason: auto-install LSP server
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = { "nomicfoundation-solidity-language-server" },
    },
  },

  -- Formatter: forge fmt
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        solidity = { "forge_fmt" },
      },
      formatters = {
        forge_fmt = {
          command = "forge",
          args = { "fmt", "--raw", "-" },
          stdin = true,
        },
      },
    },
  },
}
