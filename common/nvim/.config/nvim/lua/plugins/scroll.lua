return {
  -- Disable snacks.scroll (has issues with rapid keypresses)
  {
    "folke/snacks.nvim",
    opts = {
      scroll = { enabled = false },
    },
  },
}
