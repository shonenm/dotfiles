return {
  "petertriho/nvim-scrollbar",
  event = "BufReadPost",
  opts = {
    handle = {
      text = "█",
      blend = 0,
      color = "#7aa2f7",
    },
    marks = {
      Search = { text = { "█", "█" }, color = "#f1fa8c" },
      Error = { text = { "█", "█" }, color = "#ff5555" },
      Warn = { text = { "█", "█" }, color = "#ffb86c" },
      Info = { text = { "█", "█" }, color = "#8be9fd" },
      Hint = { text = { "█", "█" }, color = "#50fa7b" },
      Misc = { text = { "█", "█" }, color = "#bd93f9" },
      GitAdd = { text = "█", color = "#50fa7b" },
      GitChange = { text = "█", color = "#8be9fd" },
      GitDelete = { text = "█", color = "#ff5555" },
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
