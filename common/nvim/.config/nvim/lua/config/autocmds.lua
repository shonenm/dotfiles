-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Auto reload files when changed externally
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  callback = function()
    vim.cmd("checktime")
  end,
})

-- Theme-aware icon highlight groups
-- catppuccin: integrations.mini handles it automatically
-- vscode/tokyonight: apply Material Design icon colors
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("theme_icon_colors", { clear = true }),
  callback = function(args)
    if args.match == "catppuccin" or args.match:match("^catppuccin%-") then
      return
    end

    local material_hl = {
      MiniIconsAzure = { fg = "#42a5f5" },
      MiniIconsBlue = { fg = "#519aba" },
      MiniIconsCyan = { fg = "#7fdbca" },
      MiniIconsGreen = { fg = "#8dc149" },
      MiniIconsGrey = { fg = "#4d5a5e" },
      MiniIconsOrange = { fg = "#e37933" },
      MiniIconsPurple = { fg = "#a074c4" },
      MiniIconsRed = { fg = "#cc3e44" },
      MiniIconsYellow = { fg = "#cbcb41" },
    }
    for group, val in pairs(material_hl) do
      vim.api.nvim_set_hl(0, group, val)
    end
  end,
})

-- Auto organize imports on save for TypeScript/JavaScript
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.ts", "*.tsx", "*.js", "*.jsx" },
  callback = function(args)
    local clients = vim.lsp.get_clients({ bufnr = args.buf, name = "vtsls" })
    if #clients == 0 then
      return
    end
    vim.lsp.buf.code_action({
      apply = true,
      context = { only = { "source.organizeImports" }, diagnostics = {} },
    })
  end,
})

