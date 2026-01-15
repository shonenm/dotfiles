return {
  "kevinhwang91/nvim-hlslens",
  event = "SearchWrapped",
  keys = {
    { "n", [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]], desc = "Next match" },
    { "N", [[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]], desc = "Prev match" },
    { "*", [[*<Cmd>lua require('hlslens').start()<CR>]], desc = "Search word forward" },
    { "#", [[#<Cmd>lua require('hlslens').start()<CR>]], desc = "Search word backward" },
  },
  opts = {
    calm_down = true,
    nearest_only = true,
  },
}
