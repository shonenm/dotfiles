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

  -- Catppuccin
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      transparent_background = true,
      integrations = {
        mini = { enabled = true },
        blink_cmp = true,
        gitsigns = true,
        treesitter = true,
        snacks = true,
        which_key = true,
      },
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
