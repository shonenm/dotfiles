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

    -- initial + periodic refresh
    refresh_repo_diff()
    local timer = vim.uv.new_timer()
    timer:start(30000, 30000, vim.schedule_wrap(refresh_repo_diff))
    vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained" }, {
      callback = refresh_repo_diff,
    })

    -- ── section b: branch + per-buffer diff + repo summary ──
    opts.sections.lualine_b = {
      "branch",
      {
        "diff",
        symbols = {
          added = icons.git.added,
          modified = icons.git.modified,
          removed = icons.git.removed,
        },
        source = function()
          local gitsigns = vim.b.gitsigns_status_dict
          if gitsigns then
            return {
              added = gitsigns.added,
              modified = gitsigns.changed,
              removed = gitsigns.removed,
            }
          end
        end,
      },
      {
        function()
          local d = repo_diff
          return string.format(" %d  +%d  -%d", d.files, d.added, d.removed)
        end,
        cond = function()
          return repo_diff.files > 0
        end,
        color = { fg = "#9399b2" },
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
