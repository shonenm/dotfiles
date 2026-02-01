return {
  "petertriho/nvim-scrollbar",
  event = "BufReadPost",
  opts = {
    handle = {
      blend = 0,
      color = "#3b4261",
    },
    marks = {
      Search = { color = "#ff9e64" },
      Error = { color = "#db4b4b" },
      Warn = { color = "#e0af68" },
      Info = { color = "#0db9d7" },
      Hint = { color = "#1abc9c" },
      Misc = { color = "#9d7cd8" },
      GitAdd = { color = "#9ece6a" },
      GitChange = { color = "#7aa2f7" },
      GitDelete = { color = "#db4b4b" },
    },
    handlers = {
      diagnostic = true,
      search = true,
      gitsigns = true,
    },
  },
  config = function(_, opts)
    require("scrollbar").setup(opts)
    -- Guard against invalid buffer in diagnostic handler
    local diag = require("scrollbar.handlers.diagnostic")
    local orig = diag.generic_handler
    diag.generic_handler = function(bufnr, ...)
      if bufnr ~= 0 and not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      return orig(bufnr, ...)
    end
  end,
}
