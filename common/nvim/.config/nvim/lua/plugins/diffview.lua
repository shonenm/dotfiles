return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  lazy = false,
  keys = {
    { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview Open" },
    { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File History" },
    { "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Branch History" },
    { "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Diffview Close" },
  },
  config = function()
    local actions = require("diffview.actions")
    require("diffview").setup({
      enhanced_diff_hl = true,
      view = {
        default = {
          layout = "diff2_horizontal",
          winbar_info = true,
        },
      },
      keymaps = {
        disable_defaults = false,
        view = {
          ["[c"] = "<cmd>normal! [c<cr>",
          ["]c"] = "<cmd>normal! ]c<cr>",
          ["s"] = actions.toggle_stage_entry,
          ["S"] = actions.stage_all,
          ["U"] = actions.unstage_all,
          ["X"] = actions.restore_entry,
          ["q"] = actions.close,
        },
        file_panel = {
          ["s"] = actions.toggle_stage_entry,
          ["S"] = actions.stage_all,
          ["U"] = actions.unstage_all,
          ["X"] = actions.restore_entry,
          ["[c"] = actions.prev_conflict,
          ["]c"] = actions.next_conflict,
          ["q"] = actions.close,
        },
      },
    })
  end,
}
