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

    -- Workaround: snacks.nvim explorer/diagnostics.lua does not call
    -- nvim_buf_is_valid before nvim_buf_get_name (upstream bug).
    -- The same pattern in picker/source/diagnostics.lua:12 is correct.
    -- ref: telescope.nvim#910, neovim/neovim#21454
    local snacks_diag = require("snacks.explorer.diagnostics")
    local _orig_update = snacks_diag.update
    function snacks_diag.update(cwd)
      local ok, result = pcall(_orig_update, cwd)
      return ok and result or false
    end

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
