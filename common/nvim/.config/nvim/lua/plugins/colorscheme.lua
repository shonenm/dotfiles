return {
  -- TokyoNight
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      transparent = true,
      terminal_colors = true,
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        sidebars = "transparent",
        floats = "transparent",
      },
      on_highlights = function(hl, _)
        hl.Normal = { bg = "none" }
        hl.NormalFloat = { bg = "none" }
        hl.NormalNC = { bg = "none" }
      end,
    },
  },

  -- VS Code Dark Modern
  {
    "Mofiqul/vscode.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "dark",
      transparent = true,
      italic_comments = true,
    },
  },

  -- Set default colorscheme
  -- Switch with <leader>uC
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "vscode",
    },
  },
}
