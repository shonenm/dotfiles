-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- Disable built-in spell check for markdown etc. (Japanese text gets flagged as SpellBad)
vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Auto reload files when changed externally (on focus)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  callback = function()
    vim.cmd("checktime")
  end,
})

-- File watcher for background changes (e.g., tmux other pane, external tools)
-- Uses fs_event to detect changes even when nvim is not focused
local file_watchers = {}

local function watch_file(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" or file_watchers[bufnr] then
    return
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end

  local function on_change(err)
    if err then
      return
    end
    -- Stop to avoid multiple triggers
    handle:stop()
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.cmd, "checktime " .. bufnr)
      end
    end)
    -- Restart watching after debounce
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(bufnr) and file_watchers[bufnr] then
        pcall(function()
          handle:start(path, {}, on_change)
        end)
      end
    end, 100)
  end

  handle:start(path, {}, on_change)
  file_watchers[bufnr] = handle
end

local function unwatch_file(bufnr)
  local handle = file_watchers[bufnr]
  if handle then
    handle:stop()
    handle:close()
    file_watchers[bufnr] = nil
  end
end

vim.api.nvim_create_autocmd("BufReadPost", {
  group = vim.api.nvim_create_augroup("file_watcher", { clear = true }),
  callback = function(ev)
    watch_file(ev.buf)
  end,
})

vim.api.nvim_create_autocmd("BufDelete", {
  group = "file_watcher",
  callback = function(ev)
    unwatch_file(ev.buf)
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

-- Auto delete empty [No Name] buffers when hidden
vim.api.nvim_create_autocmd("BufHidden", {
  group = vim.api.nvim_create_augroup("delete_noname_buf", { clear = true }),
  callback = function(event)
    local buf = event.buf
    if
      vim.bo[buf].buftype == ""
      and vim.api.nvim_buf_get_name(buf) == ""
      and not vim.bo[buf].modified
      and vim.api.nvim_buf_line_count(buf) <= 1
      and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
    then
      vim.schedule(function()
        pcall(vim.api.nvim_buf_delete, buf, { force = false })
      end)
    end
  end,
})

-- Auto organize imports on save for TypeScript/JavaScript
-- Uses filter+apply to execute synchronously before conform.nvim formatting
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.ts", "*.tsx", "*.js", "*.jsx" },
  callback = function(args)
    local clients = vim.lsp.get_clients({ bufnr = args.buf, name = "tsgo" })
    if #clients == 0 then
      return
    end
    local params = vim.lsp.util.make_range_params()
    params.context = { only = { "source.organizeImports" }, diagnostics = {} }
    local result = clients[1]:request_sync("textDocument/codeAction", params, 3000, args.buf)
    if result and result.result and result.result[1] then
      local action = result.result[1]
      if action.edit then
        vim.lsp.util.apply_workspace_edit(action.edit, clients[1].offset_encoding)
      elseif action.command then
        clients[1]:exec_cmd(action.command)
      end
    end
  end,
})

-- Auto-close Lazy popup when focus is lost
vim.api.nvim_create_autocmd("BufLeave", {
  group = vim.api.nvim_create_augroup("lazy_auto_close", { clear = true }),
  callback = function()
    if vim.bo.filetype == "lazy" then
      local view = require("lazy.view")
      if view.view then
        view.view:close()
      end
    end
  end,
})

-- :ProfileStart → カーソル移動等を操作 → :ProfileStop で profile.log に出力
vim.api.nvim_create_user_command("ProfileStart", function()
  vim.cmd("profile start /tmp/nvim-profile.log")
  vim.cmd("profile func *")
  vim.cmd("profile file *")
end, {})

vim.api.nvim_create_user_command("ProfileStop", function()
  vim.cmd("profile pause")
  vim.notify("Profile saved to /tmp/nvim-profile.log", vim.log.levels.INFO)
end, {})

-- Large file optimization (disable heavy features for files > 100KB)
-- Improves performance on remote/SSH connections
vim.api.nvim_create_autocmd("BufReadPre", {
  group = vim.api.nvim_create_augroup("large_buf_optimization", { clear = true }),
  callback = function()
    local max_filesize = 100 * 1024 -- 100KB
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then
      return
    end
    local ok, stats = pcall(vim.uv.fs_stat, filepath)
    if ok and stats and stats.size > max_filesize then
      vim.b.large_buf = true
      -- Disable syntax highlighting
      vim.cmd("syntax off")
      -- Disable filetype detection (prevents LSP auto-attach)
      vim.opt_local.filetype = ""
      -- Disable swap and undo for large files
      vim.opt_local.swapfile = false
      vim.opt_local.undofile = false
      -- Disable fold computation
      vim.opt_local.foldmethod = "manual"
      vim.opt_local.foldexpr = "0"
      vim.notify(
        string.format("Large file detected (%.1fKB) - heavy features disabled", stats.size / 1024),
        vim.log.levels.WARN
      )
    end
  end,
})

-- Cursor visibility enhancement
-- Mode-specific cursor colors matching vscode.nvim lualine theme
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("cursor_visibility", { clear = true }),
  callback = function()
    local cursor_hl = {
      Cursor = { fg = "#1F1F1F", bg = "#0a7aca" },  -- Normal: blue
      lCursor = { fg = "#1F1F1F", bg = "#0a7aca" },
      iCursor = { fg = "#1F1F1F", bg = "#4EC9B0" }, -- Insert: green
      vCursor = { fg = "#1F1F1F", bg = "#ffaf00" }, -- Visual: yellow
      rCursor = { fg = "#1F1F1F", bg = "#f44747" }, -- Replace: red
      CursorLine = { bg = "#2a2a2a" },
      CursorLineNr = { fg = "#FFFFFF", bold = true },
    }
    for group, val in pairs(cursor_hl) do
      vim.api.nvim_set_hl(0, group, val)
    end
  end,
})

