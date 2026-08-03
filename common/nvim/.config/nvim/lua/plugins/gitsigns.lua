return {
  "lewis6991/gitsigns.nvim",
  keys = {
    {
      "<leader>uB",
      function()
        require("gitsigns").toggle_current_line_blame()
      end,
      desc = "Toggle Git Blame Line",
    },
  },
  opts = {
    current_line_blame = false,
    current_line_blame_opts = {
      virt_text = true,
      virt_text_pos = "eol",
      delay = 500,
      ignore_whitespace = false,
    },
    current_line_blame_formatter = "<author>, <author_time:%R> - <summary>",
  },
}
