return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        tinymist = {
          settings = {
            exportPdf = "onSave",
            formatterMode = "typstyle",
          },
        },
      },
    },
  },
}
