-- Session manager function
local function open_session_manager()
  local resession = require("resession")
  local sessions = resession.list()

  if #sessions == 0 then
    vim.notify("No sessions found", vim.log.levels.WARN)
    return
  end

  vim.ui.select(sessions, {
    prompt = "Sessions:",
    format_item = function(item)
      return "  " .. item
    end,
  }, function(selected)
    if not selected then
      return
    end

    vim.ui.select({ "Load", "Delete", "Rename" }, {
      prompt = "Action for '" .. selected .. "':",
    }, function(action)
      if not action then
        return
      end

      if action == "Load" then
        resession.load(selected)
        vim.notify("Session loaded: " .. selected, vim.log.levels.INFO)
      elseif action == "Delete" then
        vim.ui.select({ "Yes", "No" }, { prompt = "Delete '" .. selected .. "'?" }, function(confirm)
          if confirm == "Yes" then
            resession.delete(selected)
            vim.notify("Session deleted: " .. selected, vim.log.levels.INFO)
          end
        end)
      elseif action == "Rename" then
        vim.ui.input({ prompt = "New name: ", default = selected }, function(new_name)
          if new_name and new_name ~= "" and new_name ~= selected then
            local data_dir = vim.fn.stdpath("data")
            local old_path = data_dir .. "/session/" .. selected .. ".json"
            local new_path = data_dir .. "/session/" .. new_name .. ".json"
            if vim.fn.rename(old_path, new_path) == 0 then
              vim.notify("Session renamed: " .. selected .. " -> " .. new_name, vim.log.levels.INFO)
            else
              vim.notify("Failed to rename session", vim.log.levels.ERROR)
            end
          end
        end)
      end
    end)
  end)
end

return {
  -- Disable LazyVim's default persistence.nvim
  { "folke/persistence.nvim", enabled = false },

  -- resession.nvim for session management
  {
    "stevearc/resession.nvim",
    lazy = false,
    keys = {
      { "<leader>qs", open_session_manager, desc = "Session Manager" },
      {
        "<leader>qS",
        function()
          vim.ui.input({ prompt = "Session name: " }, function(name)
            if name and name ~= "" then
              require("resession").save(name)
              vim.notify("Session saved: " .. name, vim.log.levels.INFO)
            end
          end)
        end,
        desc = "Save Session (named)",
      },
    },
    opts = {
      autosave = {
        enabled = true,
        interval = 120,
        notify = false,
      },
      dir = "session",
      extensions = {
        quickfix = {},
      },
    },
    config = function(_, opts)
      local resession = require("resession")
      resession.setup(opts)

      -- Auto save session on exit (per directory)
      vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
          resession.save(vim.fn.getcwd(), { dir = "dirsession", notify = false })
        end,
      })
    end,
  },
}
