return {
  "declancm/cinnamon.nvim",
  version = "*",
  event = "VeryLazy",
  opts = {
    keymaps = {
      basic = true,  -- C-u, C-d, C-b, C-f, gg, G, 0, ^, $, zz, zt, zb
      extra = false,
    },
    options = {
      mode = "cursor",  -- カーソルとウィンドウを同期
      delay = 5,
      max_delta = {
        time = 150,  -- 最大アニメーション時間 (ms)
      },
    },
  },
}
