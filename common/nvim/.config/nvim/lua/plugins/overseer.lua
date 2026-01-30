return {
  "stevearc/overseer.nvim",
  cmd = { "OverseerRun", "OverseerToggle", "OverseerOpen", "OverseerClose", "OverseerBuild", "OverseerQuickAction" },
  keys = {
    { "<leader>or", "<cmd>OverseerRun<cr>", desc = "Run Task" },
    { "<leader>ot", "<cmd>OverseerToggle<cr>", desc = "Toggle Task List" },
    { "<leader>ob", "<cmd>OverseerBuild<cr>", desc = "Build Task" },
    { "<leader>oa", "<cmd>OverseerQuickAction<cr>", desc = "Task Quick Action" },
    {
      "<leader>ol",
      function()
        local overseer = require("overseer")
        local tasks = overseer.list_tasks({ recent_first = true })
        if #tasks > 0 then
          overseer.run_action(tasks[1], "open float")
        end
      end,
      desc = "Open Last Task Output",
    },
  },
  opts = {
    task_list = {
      direction = "bottom",
      min_height = 15,
      max_height = 25,
      default_detail = 1,
    },
    -- Auto-detect .vscode/tasks.json, Makefile, package.json scripts
    templates = { "builtin" },
  },
}
