-- Claude AI integration via avante.nvim
return {
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    version = false,
    build = "make",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "echasnovski/mini.icons",
    },
    opts = {
      provider = "claude",
      claude = {
        model = "claude-sonnet-4-20250514",
        max_tokens = 4096,
      },
      -- Avoid conflict with CopilotChat (<leader>a prefix)
      mappings = {
        ask = "<leader>aa",
        edit = "<leader>ae",
        refresh = "<leader>ar",
      },
    },
  },
}
