return {
  -- Disable 3rd/image.nvim (replaced by snacks.nvim image module)
  { "3rd/image.nvim", enabled = false },

  -- Enable snacks.nvim image module (SSH auto-detection, floating preview)
  {
    "folke/snacks.nvim",
    opts = {
      image = {
        enabled = true,
        doc = {
          enabled = true,
          inline = false,
          float = true,
          max_width = 80,
          max_height = 30,
        },
      },
    },
  },
}
