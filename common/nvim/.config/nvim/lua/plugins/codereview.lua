return {
  -- 起動時は :CodeReview と <Plug> mapping を定義するだけなので遅延ロードしない。
  -- <leader>gd は codediff.lua で snacks_picker から外してある。
  {
    "shonenm/codereview.nvim",
    version = "*",
    lazy = false,
    keys = { { "<leader>gd", "<cmd>CodeReview<cr>", desc = "CodeReview Open" } },
  },
}
