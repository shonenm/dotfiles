return {
  "jay-babu/mason-nvim-dap.nvim",
  dependencies = {
    "williamboman/mason.nvim",
    "mfussenegger/nvim-dap",
  },
  config = function()
    require("mason-nvim-dap").setup({
      automatic_setup = true,
      handlers = {}, -- 自動セットアップ有効（必要に応じて個別定義も可）
    })
  end,
}
