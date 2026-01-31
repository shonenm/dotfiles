return {
  "johnseth97/gh-dash.nvim",
  lazy = true,
  keys = {
    {
      "<leader>gH",
      function()
        require("gh_dash").toggle()
      end,
      desc = "GH Dash Toggle",
    },
  },
  opts = {
    keymaps = {},
    border = "rounded",
    width = 0.85,
    height = 0.85,
    autoinstall = true,
  },
}
