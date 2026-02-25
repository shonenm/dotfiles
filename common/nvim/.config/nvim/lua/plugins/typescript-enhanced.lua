-- TypeScript: tsgo (TypeScript 7 native LSP)
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        vtsls = false,
        tsgo = {},
      },
    },
  },
}
