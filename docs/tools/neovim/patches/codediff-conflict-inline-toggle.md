# codediff.nvim: Conflict view 3-way ↔ inline toggle

- **ファイル**: `common/nvim/.config/nvim/lua/plugins/codediff.lua`
- **対象**: `esmuellert/codediff.nvim` - conflict resolution view
- **症状**: Conflict 解決ビューが 3-way（theirs | ours | result）のみで、VSCode のような inline 表示（1 ペインに conflict マーカー付き）への切り替えができない
- **原因**: codediff.nvim に inline conflict view 機能が未実装
- **対処**: `config` 関数内で以下の monkey-patch を追加:
  1. `cv` キーマップで 3-way ↔ inline を切り替える `toggle_conflict_view` 関数を定義
  2. **3-way → inline**: `eventignore` で cleanup autocmd を抑制し、`codediff_restore` マーカーを全除去してから original_win と result_win を閉じ、modified_win に実ファイル（conflict markers 付き）を `:edit` で読み込み。git-conflict.nvim が自動的にマーカーを検出・ハイライト
  3. **inline → 3-way**: `leftabove vsplit` で新しい original_win を作成し、`codediff_restore` マーカーを設定後、`view.update` で仮想バッファ読み込み・result window 作成・keymaps 設定を実行
  4. `conflict.setup_keymaps` を monkey-patch して全 conflict バッファに `cv` キーマップを自動追加
  5. `update_help_line` を拡張し、`session._inline_mode` 時に inline 用ヘルプラインを表示
  6. `explorer.on_file_select` をラップし、inline mode 中のファイル選択時に自動的に 3-way へ復帰
- **cleanup 回避戦略**: `eventignore` で WinClosed/BufEnter を抑制 + `codediff_restore` マーカー全除去。`count_diff_windows()` が 0 を返すため、BufEnter fallback の `count == 1` 条件をバイパス
- **参考**: なし（upstream 機能リクエスト未作成）
- **削除条件**: codediff.nvim upstream で inline conflict view 切り替え機能が実装されたら削除
