return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  opts = function(_, opts)
    local icons = LazyVim.config.icons

    -- ── repo-wide git diff cache ────────────────────────────
    local repo_diff = { files = 0, added = 0, removed = 0 }

    local function refresh_repo_diff()
      vim.system(
        { "git", "diff", "--numstat" },
        { text = true, cwd = LazyVim.root.get() },
        function(out)
          if out.code ~= 0 then return end
          local files, added, removed = 0, 0, 0
          for line in (out.stdout or ""):gmatch("[^\n]+") do
            local a, r = line:match("^(%d+)%s+(%d+)")
            if a and r then
              files = files + 1
              added = added + tonumber(a)
              removed = removed + tonumber(r)
            end
          end
          repo_diff = { files = files, added = added, removed = removed }
        end
      )
    end

    -- Refresh on meaningful repository events. Avoid polling git forever,
    -- especially on large repositories and remote filesystems.
    refresh_repo_diff()
    vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained" }, {
      callback = refresh_repo_diff,
    })

    -- ── section b: branch + repo summary ───────────────────
    opts.sections.lualine_b = {
      "branch",
      {
        function()
          return string.format(" %d", repo_diff.files)
        end,
        cond = function() return repo_diff.files > 0 end,
        color = { fg = "#9399b2" },
        padding = { left = 1, right = 0 },
      },
      {
        function()
          return string.format("+%d", repo_diff.added)
        end,
        cond = function() return repo_diff.files > 0 end,
        color = { fg = "#9ece6a" },
        padding = { left = 1, right = 0 },
      },
      {
        function()
          return string.format("-%d", repo_diff.removed)
        end,
        cond = function() return repo_diff.files > 0 end,
        color = { fg = "#db4b4b" },
        padding = { left = 1, right = 1 },
      },
    }

    -- ── section x: remove diff, add copilot ─────────────────
    local lualine_x = {}
    for _, comp in ipairs(opts.sections.lualine_x or {}) do
      if not (type(comp) == "table" and comp[1] == "diff") then
        lualine_x[#lualine_x + 1] = comp
      end
    end

    table.insert(
      lualine_x,
      2,
      LazyVim.lualine.status(LazyVim.config.icons.kinds.Copilot, function()
        local clients = package.loaded["copilot"]
            and vim.lsp.get_clients({ name = "copilot", bufnr = 0 })
          or {}
        if #clients > 0 then
          local status = require("copilot.status").data.status
          return (status == "InProgress" and "pending")
            or (status == "Warning" and "error")
            or "ok"
        end
      end)
    )

    opts.sections.lualine_x = lualine_x

    opts.sections.lualine_c = {
      {
        function()
          local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
          local explorer = ok and lifecycle.get_explorer and lifecycle.get_explorer(vim.api.nvim_get_current_tabpage()) or nil
          return explorer and explorer.current_file_path or ""
        end,
        cond = function()
          local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
          local explorer = ok and lifecycle.get_explorer and lifecycle.get_explorer(vim.api.nvim_get_current_tabpage()) or nil
          local target = explorer and explorer.target_revision
          return explorer
            and explorer.base_revision
            and explorer.current_file_path
            and target
            and not tostring(target):match("^:[0-3]$")
            and (target ~= "WORKING" or vim.env.LIVE_PR_REVIEW == "1")
            or false
        end,
      },
      {
        "filename",
        cond = function()
          local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
          local explorer = ok and lifecycle.get_explorer and lifecycle.get_explorer(vim.api.nvim_get_current_tabpage()) or nil
          local target = explorer and explorer.target_revision
          return not (
            explorer
            and explorer.base_revision
            and explorer.current_file_path
            and target
            and not tostring(target):match("^:[0-3]$")
            and (target ~= "WORKING" or vim.env.LIVE_PR_REVIEW == "1")
          )
        end,
      },
    }

    -- ── section y: lsp + encoding/format + position ─────────
    local lsp_names = {}

    opts.sections.lualine_y = {
      {
        function()
          return table.concat(lsp_names, ", ")
        end,
        icon = " ",
        cond = function()
          lsp_names = {}
          for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
            if client.name ~= "copilot" then
              lsp_names[#lsp_names + 1] = client.name
            end
          end
          return #lsp_names > 0
        end,
      },
      {
        "encoding",
        cond = function()
          local enc = vim.opt.fileencoding:get()
          return enc ~= "" and enc ~= "utf-8"
        end,
        padding = { left = 1, right = 0 },
      },
      {
        "fileformat",
        cond = function()
          return vim.bo.fileformat ~= "unix"
        end,
        padding = { left = 1, right = 0 },
      },
      { "progress", separator = " ", padding = { left = 1, right = 0 } },
      { "location", padding = { left = 0, right = 1 } },
    }
  end,
}
