return {
  "nvim-tree/nvim-tree.lua",
  event = "VeryLazy",
  dependencies = {"nvim-tree/nvim-web-devicons"},
  keys = {
    { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "TreeToggle" },
  },
  config = function()
    -- disable netrw at the very start of your init.lua
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1

    require("nvim-tree").setup()
  end
}
