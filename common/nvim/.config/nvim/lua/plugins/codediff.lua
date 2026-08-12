return {
  -- Disable snacks_picker's <leader>gd (Git Diff hunks) to free it for CodeDiff.
  -- Reserve the first three rows for CodeDiff's fixed hunk indicator and wrap
  -- long notifications instead of clipping them at the screen edge.
  {
    "folke/snacks.nvim",
    keys = { { "<leader>gd", false } },
    opts = {
      notifier = { margin = { top = 3, right = 1, bottom = 0 } },
      styles = { notification = { wo = { wrap = true } } },
    },
  },
  {
    "esmuellert/codediff.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    cmd = { "CodeDiff", "CodeReview", "CodeReviewBranch" },
    keys = {
      { "<leader>gd", desc = "CodeDiff Open" },
      { "<leader>gf", "<cmd>CodeDiff history %<cr>", desc = "File History" },
      { "<leader>gF", "<cmd>CodeDiff history<cr>", desc = "Commit History" },
    },
    opts = {
      explorer = {
        view_mode = "tree",
        indent_markers = true,
      },
    },
    config = function(_, opts)
      require("config.codediff").setup(opts)
    end,
  },
}
