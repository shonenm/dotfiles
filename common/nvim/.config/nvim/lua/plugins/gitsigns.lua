return {
  "lewis6991/gitsigns.nvim",
  keys = {
    -- Disable default <leader>gd (diffthis) to free it for CodeDiff
    { "<leader>gd", false },
  },
  opts = {
    current_line_blame = true,
    current_line_blame_opts = {
      virt_text = true,
      virt_text_pos = "eol",
      delay = 500,
      ignore_whitespace = false,
    },
    current_line_blame_formatter = "<author>, <author_time:%R> - <summary>",
  },
}
