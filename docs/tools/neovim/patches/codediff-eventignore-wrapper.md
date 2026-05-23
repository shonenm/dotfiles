# codediff.nvim: 外部プラグインとの競合によるエラー

- **ファイル**: `common/nvim/.config/nvim/lua/plugins/codediff.lua`
- **対象**: `esmuellert/codediff.nvim` - `lua/codediff/ui/view/init.lua`
- **症状**: CodeDiff で仮想ファイル（staged 変更等）を選択すると、package-info.nvim 等の外部プラグインが BufEnter でエラーを出す
- **原因**: view.update が仮想ファイルバッファを読み込む際に BufEnter/WinEnter イベントが発火し、外部プラグインが通常ファイルを期待してエラー
- **対処**: `config` 関数内で `view.update` をラップし、呼び出し前後で `vim.o.eventignore = "BufEnter,WinEnter"` を設定。オリジナルの view.update ロジックはそのまま使用し、イベント抑制のみを追加
- **副作用対策**: eventignore により WinEnter が抑制されるため、on_file_select もラップして CodeDiffVirtualFileLoaded イベント + defer_fn でフォーカスを explorer に復元
- **参考**: なし（upstream issue 未作成）
- **削除条件**: codediff.nvim upstream で仮想ファイル読み込み時のイベント制御が改善されたら削除
