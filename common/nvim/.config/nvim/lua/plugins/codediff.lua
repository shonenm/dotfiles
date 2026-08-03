return {
  -- Disable snacks_picker's <leader>gd (Git Diff hunks) to free it for CodeDiff
  { "folke/snacks.nvim", keys = { { "<leader>gd", false } } },
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
