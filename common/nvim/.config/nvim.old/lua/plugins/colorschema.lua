-- ~/.config/nvim/lua/plugins/colorscheme.lua
return {
  {
    "folke/tokyonight.nvim",
    lazy = false, -- 起動時に即ロード
    priority = 1000, -- 最優先で読み込む
    config = function()
      vim.cmd.colorscheme("tokyonight") -- スタイルを変えるならここを"tokyonight-night"などに
    end,
  },
}
