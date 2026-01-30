return {
  -- GraphQL LSP
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        graphql = {
          filetypes = { "graphql", "typescriptreact", "javascriptreact", "typescript", "javascript" },
        },
      },
    },
  },
  -- GraphQL treesitter parser
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = { "graphql" },
    },
  },
}
