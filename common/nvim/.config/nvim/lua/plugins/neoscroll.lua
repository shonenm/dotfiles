return {
  "karb94/neoscroll.nvim",
  event = "VeryLazy",
  opts = {
    easing = "quadratic",
  },
  config = function(_, opts)
    local neoscroll = require("neoscroll")
    local scroll_state = require("neoscroll.scroll")
    neoscroll.setup(opts)

    local modes = { "n", "v", "x" }
    vim.keymap.set(modes, "<C-d>", function()
      if scroll_state.scrolling then return end
      neoscroll.scroll(20, { duration = 100 })
    end, { desc = "Scroll down 10 lines" })
    vim.keymap.set(modes, "<C-u>", function()
      if scroll_state.scrolling then return end
      neoscroll.scroll(-20, { duration = 100 })
    end, { desc = "Scroll up 10 lines" })
  end,
}
