-- TypeScript: vtsls import preferences (VSCode parity)
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        vtsls = {
          settings = {
            typescript = {
              preferences = {
                importModuleSpecifier = "non-relative",
              },
              updateImportsOnFileMove = { enabled = "always" },
            },
            javascript = {
              preferences = {
                importModuleSpecifier = "non-relative",
              },
              updateImportsOnFileMove = { enabled = "always" },
            },
          },
        },
      },
    },
  },
}
