return {
  "folke/snacks.nvim",
  opts = {
    explorer = {
      hidden = true,
      ignored = true,
    },
    picker = {
      sources = {
        files = {
          hidden = true,
        },
        explorer = {
          hidden = true,
          ignored = true,
        },
      },
    },
    indent = {
      enabled = false,
    },
    terminal = {
      win = {
        position = "float",
        border = "rounded",
      },
    },
  },
  config = function(_, opts)
    require("snacks").setup(opts)
    local function set_explorer_hl()
      -- hidden ファイル（dotfiles）は通常表示
      vim.api.nvim_set_hl(0, "SnacksPickerPathHidden", { link = "Normal" })
      -- ignored ファイル（.gitignore）は薄暗く表示
      vim.api.nvim_set_hl(0, "SnacksPickerPathIgnored", { link = "Comment" })
    end
    set_explorer_hl()
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = set_explorer_hl,
    })
  end,
}
