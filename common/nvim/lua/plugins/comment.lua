return {
  {
    "numToStr/Comment.nvim",
    event = "VeryLazy",
    config = function()
      require("Comment").setup({
        -- 基本設定
        padding = true, -- コメント記号の前後にスペースを追加
        sticky = true, -- カーソルの位置を保持
        ignore = nil, -- 特定の行を無視
        toggler = {
          line = "gcc", -- 行コメントのトグル
          block = "gbc", -- ブロックコメントのトグル
        },
        opleader = {
          line = "gc", -- ビジュアルモードでの行コメント
          block = "gb", -- ビジュアルモードでのブロックコメント
        },
        extra = {
          above = "gcO", -- 現在の行の上にコメントを追加
          below = "gco", -- 現在の行の下にコメントを追加
          eol = "gcA", -- 行末にコメントを追加
        },
        mappings = {
          basic = true, -- デフォルトのマッピングを有効化
          extra = true, -- 追加のマッピングを有効化
          extended = false, -- 拡張マッピングを無効化
        },
        pre_hook = nil, -- コメント前に実行するフック
        post_hook = nil, -- コメント後に実行するフック
      })
    end,
  },
}
