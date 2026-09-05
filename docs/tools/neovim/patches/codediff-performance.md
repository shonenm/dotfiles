# codediff.nvim: パフォーマンス最適化

> **由来:** **Plugin** codediff.nvim / **Local patch** performance override（[区分](../../../provenance.md#区分)）

- **ファイル**: `common/nvim/.config/nvim/lua/config/codediff.lua`
- **対象**: `esmuellert/codediff.nvim`
- **症状**: 大きなファイルや連続操作時に差分計算が遅延し、UIがもたつく
- **原因**: Lua側の処理が律速（UTF-16変換、extmark適用、auto_refreshの頻繁な発火）

## 実装した最適化

### Phase 1: 設定レベル

1. ~~**debounce値の調整**~~ → Phase 3.5 で CursorMoved 自動切替自体を廃止したため削除

2. **大ファイル警告**
   - `on_file_select`ラッパー内でファイルサイズをチェック
   - 75KB超（約1500行）のファイル選択時に警告を表示
   - 同一ファイルへの警告は1回のみ

### Phase 2: monkey-patch

1. **auto_refresh throttle調整** (200ms → 400ms)
   - `auto_refresh.enable`をラップして独自のthrottleタイマーを使用
   - 編集中の差分再計算頻度を50%削減

2. **差分結果キャッシュ**
   - `render.compute_and_render`をラップ
   - ファイルパス + リビジョン + changedtickをキーにLRUキャッシュ（最大20エントリ）
   - 同じファイルに戻った際に再計算をスキップ

3. **変更通知と再描画の分離**
   - v3.1.1はnative watcherの全通知を `force=true` に変換するため、コミット間比較でも無関係なworktree/indexの変更で再描画される
   - localの `_refresh_once` wrapperで表示中の入力を確認し、比較SHA・WORKING buffer・index内容が変わったときだけforceする。upstreamのstatus比較・直列schedulerは維持
   - WORKINGは表示中bufferへの `checktime`、indexは内容比較で確認する。ファイル一覧や追加・削除行数が同じ変更も検出する
   - review中のglobal `autoread` 設定は維持し、確認時だけ対象bufferのlocal値を有効化して元に戻す。未保存bufferは再読込しない
   - 自動更新の `no_jump=true` はlocalのフォーカス復元タイマーを通さず、操作位置を維持する
   - hunk count更新後の追加描画は、カウントが変わったときだけ行う

### Phase 3: git操作キャッシュ

根本原因: mutable revision (`:0`) のキャッシュバイパスにより `git show :0:<path>` がファイル選択のたびに実行、`git rev-parse --verify HEAD` も毎回実行されていた。

1. **mutable revision の generation-based キャッシュ** (Patch 1)
   - `git.get_file_content` をラップし、`:0` 等のmutable revisionにもキャッシュを適用
   - `mutable_generation` カウンタで無効化を制御
   - staging操作 (`gs`/`gr`/`gu`/`-`/`S`/`U`/`X`) とrefresh開始時にインクリメントし、外部のindex変更も反映する

2. **resolve_revision の結果キャッシュ** (Patch 2)
   - `git.resolve_revision` をラップし、`git rev-parse --verify HEAD` の結果をキャッシュ
   - `cc`/`ca` (commit) とrefresh開始時に無効化し、外部commit後もHEADを再解決する

3. **gs/gr のタイミング修正** (Patch 3)
   - `vim.cmd("Gitsigns stage_hunk")` → `require("gitsigns").stage_hunk(range, {}, callback)` に変更
   - gitsigns Lua API の callback で git 完了後にのみ `refresh_diff_view` を発火
   - visual mode 対応（range パラメータを渡す）
   - `mk_repeatable` ラッパーが callback 含む全引数をキャプチャするため dot-repeat も動作

4. **hunk_counts のフォールバック参照** (Patch 4)
   - `prepare_node` でハンクカウント参照時、主グループのキャッシュが miss した場合に反対側グループ (staged↔unstaged) もフォールバック参照
   - optimistic stage/unstage 直後のキャッシュキー不一致による表示消失を防止
   - 注: 当初 `mutable_generation` による generation-based スキップを実装していたが、ファイル編集後にカウントが更新されない問題があったため削除。既存の debounce/throttle で実行頻度は十分制御されている

### Phase 3.5: CursorMoved 自動 diff 切替の廃止

根本原因: CursorMoved autocmd が 750ms debounce 後に `on_file_select` → `view.update()` → `compute_and_render()`（同期 C FFI、最大 5 秒）を発火し、カーソル移動中に UI がブロックされていた。optimistic stage/unstage 後のツリー再構築でもカーソル位置変動により同じフローが発火していた。

1. **CursorMoved autocmd 削除**
   - j/k でのカーソル移動では diff ビューを一切変更しない
   - debounce_timer / debounce_ms 関連コードも削除

2. **`l` キーマップ変更**
   - 旧: diff ビューにフォーカス移動のみ（diff 切替なし）
   - 新: フォーカス中ファイルの diff に切替 + diff ビューにフォーカス移動

3. **`<CR>` キーマップ変更**
   - 旧: 即座に diff 切替 + diff ビューにフォーカス移動
   - 新: diff 未表示 → diff 切替（Explorer に留まる）、表示済み → diff ビューにフォーカス移動

### Phase 4: Optimistic stage/unstage

根本原因: Explorer での stage/unstage 操作時、git コマンド完了 → fs_event 検知 → debounce → `git status` → ツリー再構築という直列フローにより UI 更新に体感 1 秒以上かかっていた。

1. **Optimistic UI 更新**
   - `toggle_stage_entry` / `stage_all` / `unstage_all` / `toggle_stage_file` のラッパーを書き換え
   - `explorer.status_result` をインメモリで即座に更新（ファイルエントリを staged/unstaged 間で移動）
   - `create_tree_data()` でツリーを再構築し即座に `render()`（git コマンド不要）

2. **バックグラウンド git 実行**
   - `git add` / `git reset HEAD` は非同期でバックグラウンド発火
   - auto-refresh（fs_event + debounce）が後から実状態と整合

3. **explorer init モジュール同期**
   - `codediff.ui.explorer.init` がモジュールロード時に関数を静的コピーするため、パッチ後の関数を明示的に同期

4. **toggle_stage_file パッチ**（diff view の `-` キー用）
   - 元実装は async git のみで UI 更新なし
   - session からexplorer を取得し optimistic_move_file + rebuild_tree_from_status を実行
   - `explorer.current_file_group` を更新して状態整合
   - `refresh_diff_view` で diff ビューも更新

## 効果

| 最適化項目 | 効果 |
|------------|------|
| auto_refresh throttle | 編集中の計算頻度削減 |
| 差分キャッシュ | ファイル切替時の再計算スキップ |
| 大ファイル警告 | ユーザーへの事前通知 |
| CursorMoved 廃止 | カーソル移動で diff 計算が発生しない |
| mutable revision cache | ファイル選択時の `git show` スキップ |
| resolve_revision cache | ファイル選択時の `git rev-parse` スキップ |
| gs/gr callback化 | git完了後にのみdiff更新、staleデータでの二重計算を防止 |
| hunk_counts fallback | グループ移動直後のハンクカウント表示消失防止 |
| optimistic stage/unstage | Explorer の stage/unstage 操作で即座に UI 更新 |
| toggle_stage_file patch | diff view の `-` キーでも optimistic 更新 + diff refresh |
| upstream refresh維持 | 実際の入力変更だけforce再描画し、無関係な通知では操作位置を維持 |

## 検証

```bash
python3 scripts/test-codediff-refresh.py
```

インストール済みのNeovim・codediff.nvim・nui.nvimを使い、一時Git repoでコミット間比較、WORKING、staged、外部commitを検証する。無変更通知・pollingで追加描画しないこと、同じ行数の内容変更を反映すること、フォーカス・カーソル・未保存編集を維持することを確認する。Lazy.nvimは起動せずlockfileを変更しない。

## 削除条件

- codediff.nvim upstreamでパフォーマンス改善（extmarkバッチ処理、UTF-16変換キャッシュ等）が実装されたら削除を検討
- 参考: upstreamへのIssue/PR作成を推奨
