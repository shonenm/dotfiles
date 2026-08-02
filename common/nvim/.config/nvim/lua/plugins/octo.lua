return {
  {
    "pwntester/octo.nvim",
    opts = {
      use_local_fs = true,
      default_to_projects_v2 = false,
    },
    keys = {
      { "<leader>gc", "<cmd>Octo pr checks<cr>", desc = "PR Checks (Octo)" },
      { "<leader>gw", "<cmd>Octo run list<cr>", desc = "Workflow Runs (Octo)" },
    },
  },
}
