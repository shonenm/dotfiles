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
      group_overrides = {
        -- VSCode-like diff highlighting
        -- 追加行: 緑系の背景
        DiffAdd = { fg = "NONE", bg = "#2d4a2d" },
        -- 変更行全体: 暗い青系（行全体のマーカー）
        DiffChange = { fg = "NONE", bg = "#1e3a50" },
        -- 削除行: 赤系の背景
        DiffDelete = { fg = "NONE", bg = "#4a2d2d" },
        -- 変更箇所（行内）: より明るい青/シアン系で強調
        DiffText = { fg = "NONE", bg = "#2d5a7a" },
      },
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
