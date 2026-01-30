return {
  "stevearc/overseer.nvim",
  cmd = { "OverseerRun", "OverseerToggle", "OverseerOpen", "OverseerClose" },
  keys = {
    { "<leader>or", "<cmd>OverseerRun<cr>", desc = "Run Task" },
    { "<leader>ot", "<cmd>OverseerToggle<cr>", desc = "Toggle Task List" },
  },
  opts = {
    task_list = {
      direction = "bottom",
      min_height = 15,
      default_detail = 1,
    },
    -- Auto-detect .vscode/tasks.json, Makefile, package.json scripts
    templates = { "builtin" },
  },
}
