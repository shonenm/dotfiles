return {
  {
    "Bekaboo/dropbar.nvim",
    event = "BufReadPost",
    opts = {
      sources = {
        path = {
          relative_to = function(_, win)
            local ok, cwd = pcall(vim.fn.getcwd, win)
            return ok and cwd or vim.fn.getcwd()
          end,
        },
      },
    },
  },
}
