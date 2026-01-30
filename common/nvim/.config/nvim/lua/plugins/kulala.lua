return {
  "mistweaverco/kulala.nvim",
  ft = "http",
  keys = {
    { "<leader>hr", "<cmd>lua require('kulala').run()<cr>", desc = "Run HTTP Request", ft = "http" },
    { "<leader>ha", "<cmd>lua require('kulala').run_all()<cr>", desc = "Run All Requests", ft = "http" },
    { "<leader>he", "<cmd>lua require('kulala').set_selected_env()<cr>", desc = "Select Environment", ft = "http" },
  },
  opts = {},
}
