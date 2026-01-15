return {
  "shellRaining/hlchunk.nvim",
  event = { "BufReadPre", "BufNewFile" },
  opts = {
    chunk = {
      enable = true,
      style = {
        { fg = "#7aa2f7" }, -- tokyonight blue
      },
    },
    indent = {
      enable = true,
      style = {
        { fg = "#3b4261" }, -- subtle gray
      },
    },
    line_num = {
      enable = false,
    },
    blank = {
      enable = false,
    },
  },
}
