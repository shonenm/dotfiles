return {
  -- Disable snacks_picker's <leader>gd (Git Diff hunks) to free it for CodeDiff
  { "folke/snacks.nvim", keys = { { "<leader>gd", false } } },
  {
  "esmuellert/codediff.nvim",
  dependencies = { "MunifTanjim/nui.nvim" },
  cmd = { "CodeDiff" },
  keys = {
    { "<leader>gd", "<cmd>CodeDiff<cr>", desc = "CodeDiff Open" },
    { "<leader>gf", "<cmd>CodeDiff history %<cr>", desc = "File History" },
    { "<leader>gF", "<cmd>CodeDiff history<cr>", desc = "Commit History" },
  },
  opts = {},
  config = function(_, opts)
    require("codediff").setup(opts)

    -- Auto-select file on cursor move (j/k updates diff instantly)
    local keymaps = require("codediff.ui.explorer.keymaps")
    local orig_setup = keymaps.setup
    keymaps.setup = function(explorer)
      orig_setup(explorer)
      local tree = explorer.tree
      local last_node_id = nil
      vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = explorer.bufnr,
        callback = function()
          local node = tree:get_node()
          if not node or not node.data then return end
          if node.data.type == "group" or node.data.type == "directory" then return end
          local node_id = node:get_id()
          if node_id == last_node_id then return end
          last_node_id = node_id
          explorer.on_file_select(node.data)
        end,
      })
    end

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "codediff-explorer",
      callback = function(ev)
        local map_opts = { buffer = ev.buf, noremap = true, silent = true, nowait = true }
        vim.keymap.set("n", "cc", "<cmd>Git commit<cr>", vim.tbl_extend("force", map_opts, { desc = "Git commit" }))
        vim.keymap.set("n", "ca", "<cmd>Git commit --amend<cr>", vim.tbl_extend("force", map_opts, { desc = "Git commit --amend" }))
      end,
    })
  end,
  },
}
