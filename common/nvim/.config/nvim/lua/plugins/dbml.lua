return {
  {
    "LazyVim/LazyVim",
    opts = function()
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "dbml",
        callback = function(ev)
          vim.keymap.set("n", "<leader>cp", function()
            local file = vim.api.nvim_buf_get_name(ev.buf)
            local svg = file:gsub("%.dbml$", ".svg")
            vim.system(
              { "dbml-renderer", "-i", file, "-o", svg },
              {},
              vim.schedule_wrap(function(result)
                if result.code ~= 0 then
                  vim.notify("dbml-renderer failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
                  return
                end
                local open_cmd = vim.fn.has("macunix") == 1 and "open" or "xdg-open"
                vim.system({ open_cmd, svg })
              end)
            )
          end, { buffer = ev.buf, desc = "DBML: render and open SVG" })
        end,
      })
    end,
  },
}
