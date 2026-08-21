# codediff.nvim: 先頭ファイルの初回自動オープンを抑制

> **由来:** **Plugin** codediff.nvim / **Local patch** 初回 auto-load の抑制（[区分](../../../provenance.md#区分)）

- **ファイル**: `common/nvim/.config/nvim/lua/config/codediff.lua`（`render_mod.create` ラッパー）
- **対象**: `esmuellert/codediff.nvim` - `lua/codediff/ui/explorer/render.lua` の explorer 作成直後の `on_file_select(initial_file)`
- **症状**: CodeDiff / CodeReview を開くと先頭ファイルの diff が勝手に開く。オフにする設定フラグが upstream に存在しない
- **原因**: `render.create` が無条件で先頭 visible file を初回選択する
- **対処**: ラップ済みの `on_file_select` で初回呼び出しを握りつぶす。`opts.focus_file` 指定時（`CodeDiff history %` や live-pr のファイル指定）のみ通す。先頭が conflict のとき 3-way view が水平分割を作る旧問題も、初回オープン抑制で同時に解消
- **参考**: なし（設定フラグの upstream 追加要望は未作成）
- **削除条件**: upstream に初回自動オープンを無効化する設定が追加されたら移行して削除
