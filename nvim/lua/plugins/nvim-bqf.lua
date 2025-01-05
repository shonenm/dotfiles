
return {
  {
    "kevinhwang91/nvim-bqf",
    ft = "qf",  -- quickfix ウィンドウでのみロード
    config = function()
      require("bqf").setup({
        auto_enable = true,  -- quickfix ウィンドウで自動有効化
        preview = {
          win_height = 12,  -- プレビューウィンドウの高さ
          win_vheight = 12, -- 縦プレビューウィンドウの高さ
          delay_syntax = 50, -- シンタックスハイライトの遅延時間 (ms)
          border_chars = { '│', '─', '╭', '╮', '╯', '╰', '│', '─' },
        },
        func_map = {
          open = "<CR>", -- Enter キーでプレビューを開く
        },
        filter = {
          fzf = {
            action_for = { ['ctrl-s'] = 'split', ['ctrl-t'] = 'tabedit', ['ctrl-v'] = 'vsplit' },
            extra_opts = { '--bind', 'ctrl-o:toggle-all', '--prompt', '> ' },
          },
        },
      })
    end,
  },
}
