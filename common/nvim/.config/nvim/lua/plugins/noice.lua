return {
  {
    "folke/noice.nvim",
    opts = {
      presets = {
        long_message_to_split = false, -- 長さベースのsplit分岐を無効化
      },
      routes = {
        -- エラーメッセージ: notify（目立つ、右上に表示）
        {
          filter = { error = true },
          view = "notify",
        },
        -- 警告メッセージ: notify
        {
          filter = { warning = true },
          view = "notify",
        },
        -- ファイル保存・読み込み: mini（右下に小さく）
        {
          filter = {
            event = "msg_show",
            any = {
              { find = "%d+L, %d+B" },
              { find = "written" },
              { find = "more lines" },
              { find = "fewer lines" },
              { find = "line less" },
              { find = "lines yanked" },
            },
          },
          view = "mini",
        },
        -- 検索結果カウント: mini
        {
          filter = { event = "msg_show", kind = "search_count" },
          view = "mini",
        },
      },
    },
  },
}
