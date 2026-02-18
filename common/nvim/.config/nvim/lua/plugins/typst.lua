return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        tinymist = {
          settings = {
            exportPdf = "onType",
            formatterMode = "typstyle",
          },
        },
      },
    },
  },
}
