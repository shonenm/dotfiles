return {
  {
    "petertriho/nvim-scrollbar",
    config = function()
      require("scrollbar").setup({
        show = true,
        show_in_active_only = false,
        set_highlights = true,
        folds = 1000, -- バッファ内の行数がこれを超える場合、フォールドの表示を無効化
        max_lines = false, -- バッファ内の行数がこれを超える場合、スクロールバーを無効化
        hide_if_all_visible = false, -- すべての行が表示されている場合に非表示にする
        throttle_ms = 100, -- 更新の頻度をミリ秒単位で制御
        handle = {
          text = " ",
          blend = 30, -- 透明度 (0 = 不透明, 100 = 完全に透明)
          color = nil,
          color_nr = nil,
          highlight = "CursorColumn",
          hide_if_all_visible = true,
        },
        marks = {
          Cursor = {
            text = "•",
            priority = 0,
            highlight = "Normal",
          },
          Search = {
            text = { "-", "=" },
            priority = 1,
            highlight = "Search",
          },
          Error = {
            text = { "-", "=" },
            priority = 2,
            highlight = "DiagnosticVirtualTextError",
          },
          Warn = {
            text = { "-", "=" },
            priority = 3,
            highlight = "DiagnosticVirtualTextWarn",
          },
          Info = {
            text = { "-", "=" },
            priority = 4,
            highlight = "DiagnosticVirtualTextInfo",
          },
          Hint = {
            text = { "-", "=" },
            priority = 5,
            highlight = "DiagnosticVirtualTextHint",
          },
          Misc = {
            text = { "-", "=" },
            priority = 6,
            highlight = "Normal",
          },
          GitAdd = {
            text = "┆",
            priority = 7,
            highlight = "GitSignsAdd",
          },
          GitChange = {
            text = "┆",
            priority = 7,
            highlight = "GitSignsChange",
          },
          GitDelete = {
            text = "▁",
            priority = 7,
            highlight = "GitSignsDelete",
          },
        },
        excluded_buftypes = {
          "terminal",
        },
        excluded_filetypes = {
          "dropbar_menu",
          "dropbar_menu_fzf",
          "DressingInput",
          "cmp_docs",
          "cmp_menu",
          "noice",
          "prompt",
          "TelescopePrompt",
        },
        autocmd = {
          render = {
            "BufWinEnter",
            "TabEnter",
            "TermEnter",
            "WinEnter",
            "CmdwinLeave",
            "TextChanged",
            "VimResized",
            "WinScrolled",
          },
          clear = {
            "BufWinLeave",
            "TabLeave",
            "TermLeave",
            "WinLeave",
          },
        },
        handlers = {
          cursor = true,
          diagnostic = true,
          gitsigns = false,
          handle = true,
          search = false,
          ale = false,
        },
      })
    end,
  },
}
