-- Markdown をエディタ内でリッチにレンダリングする。
-- LazyVim の lang.markdown extra は意図的に地味なプリセット
-- (見出しアイコンなし / sign なし / checkbox 無効) を渡すため、ここで全面的に上書きする。
-- <leader>um でトグル (LazyVim 側の config が Snacks.toggle を登録済み)。

local ft = {
  "markdown",
  "markdown.mdx",
  "norg",
  "rmd",
  "org",
  "codecompanion",
  -- AI チャットバッファも markdown として描画する
  "Avante",
  "AvanteInput",
  "copilot-chat",
}

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = ft,
    opts = {
      file_types = ft,

      -- 挿入・ビジュアルモードでも描画したまま編集する (Obsidian 的な体験)。
      -- カーソル行だけは anti_conceal で生テキストに戻る。
      render_modes = true,
      anti_conceal = {
        enabled = true,
        -- 背景系はカーソル行でも消さない (ちらつき防止)
        ignore = {
          code_background = true,
          head_background = true,
          indent = true,
          sign = true,
          virtual_lines = true,
        },
      },

      -- callout / checkbox の補完を blink.cmp と LSP に出す
      completions = {
        blink = { enabled = true },
        lsp = { enabled = true },
      },

      heading = {
        sign = true,
        signs = { "󰫎 " },
        icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
        -- inline: '#' を隠してアイコンを差し込む (本文が左端に揃う)
        position = "inline",
        -- H1/H2 はウィンドウ幅のバナー、H3 以降は文字幅のバッジ
        width = { "full", "full", "block", "block", "block", "block" },
        left_pad = 1,
        right_pad = 2,
        -- 見出しの上下に背景色の帯を追加。border_virtual = false なので
        -- 前後が空行のときだけ描画され、行数はずれない。
        border = true,
        border_virtual = false,
      },

      code = {
        -- 見出し側で sign を使うのでコードブロックは言語ラベルのみ
        sign = false,
        width = "block",
        min_width = 45,
        left_pad = 2,
        right_pad = 2,
        language_pad = 1,
        language_icon = true,
        language_name = true,
        -- hide: ``` の行は言語ラベルがある行以外を隠す
        border = "hide",
        inline_pad = 1,
        -- diff はハイライトが潰れるので背景を付けない
        disable_background = { "diff" },
      },

      bullet = {
        icons = { "●", "○", "◆", "◇" },
        right_pad = 1,
      },

      checkbox = {
        enabled = true,
        right_pad = 1,
        unchecked = { icon = "󰄱 ", highlight = "RenderMarkdownUnchecked" },
        checked = {
          icon = "󰱒 ",
          highlight = "RenderMarkdownChecked",
          scope_highlight = "@markup.strikethrough",
        },
        -- markdown 文法外の拡張状態 (Obsidian 互換)
        custom = {
          todo = { raw = "[-]", rendered = "󰥔 ", highlight = "RenderMarkdownTodo" },
          important = { raw = "[!]", rendered = "󰀦 ", highlight = "DiagnosticWarn" },
          question = { raw = "[?]", rendered = "󰘥 ", highlight = "DiagnosticInfo" },
          star = { raw = "[*]", rendered = "󰓎 ", highlight = "DiagnosticWarn" },
          cancelled = {
            raw = "[~]",
            rendered = "󰰱 ",
            highlight = "Comment",
            scope_highlight = "@markup.strikethrough",
          },
        },
      },

      quote = {
        icon = "▋",
        -- 折り返した行にも引用マーカーを継続表示する (wrap 前提)
        repeat_linebreak = true,
      },

      pipe_table = {
        preset = "round",
        cell = "padded",
        alignment_indicator = "━",
      },

      link = {
        custom = {
          notion = { icon = "󰈙 ", pattern = "notion%.so", kind = "url" },
          claude = { icon = "󰚩 ", pattern = "claude%.ai", kind = "url" },
          anthropic = { icon = "󰚩 ", pattern = "anthropic%.com", kind = "url" },
        },
      },

      -- 見出しレベルに応じて本文をインデントし、階層を可視化する。
      -- 二重線を避けるため hlchunk 側で markdown を除外している。
      indent = {
        enabled = true,
        per_level = 2,
        skip_level = 1,
        skip_heading = false,
        icon = "▏",
      },

      html = {
        comment = {
          -- コメントは畳むが、存在は小さなアイコンで示す
          conceal = true,
          text = "󰅺 ",
        },
        -- 開始/終了タグを隠してアイコンに置き換える
        tag = {
          details = { icon = "󰅀 ", highlight = "RenderMarkdownHtmlComment" },
          summary = { icon = "󰅂 ", highlight = "RenderMarkdownHtmlComment" },
          kbd = { icon = "󰌌 ", highlight = "RenderMarkdownCodeInline" },
        },
      },

      -- utftex / latex2text が未導入のため無効化 (有効のままだとエラーログが出る)
      latex = { enabled = false },
    },
  },

  -- markdown では render-markdown の indent を使うので hlchunk のガイドを止める
  {
    "shellRaining/hlchunk.nvim",
    opts = {
      indent = { exclude_filetypes = { markdown = true } },
      chunk = { exclude_filetypes = { markdown = true } },
    },
  },
}
