-- Multi-cursor editing (VSCode-like Ctrl+D / Ctrl+Shift+Up/Down)
return {
  {
    "mg979/vim-visual-multi",
    branch = "master",
    event = "VeryLazy",
    init = function()
      -- VSCode-like keybindings
      vim.g.VM_maps = {
        ["Find Under"] = "<C-n>", -- Ctrl+D equivalent
        ["Find Subword Under"] = "<C-n>",
        ["Select All"] = "<C-S-l>", -- Select all occurrences
        ["Add Cursor Down"] = "<C-S-Down>", -- Add cursor below
        ["Add Cursor Up"] = "<C-S-Up>", -- Add cursor above
        ["Skip Region"] = "<C-x>", -- Skip current match
      }
      vim.g.VM_theme = "neon"
    end,
  },
}
