# codediff.nvim: パフォーマンス最適化

- **ファイル**: `common/nvim/.config/nvim/lua/plugins/codediff.lua`
- **対象**: `esmuellert/codediff.nvim`
- **症状**: 大きなファイルや連続操作時に差分計算が遅延し、UIがもたつく
- **原因**: Lua側の処理が律速（UTF-16変換、extmark適用、auto_refreshの頻繁な発火）

## 実装した最適化

### Phase 1: 設定レベル

1. **debounce値の調整** (400ms → 750ms)
   - `keymaps.setup`内の`debounce_ms`を750msに増加
   - 連続でj/k操作した際の差分計算を大幅に削減
   - Enterキーで即座に反映（debounceをスキップ）

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

## 効果

| 最適化項目 | 効果 |
|------------|------|
| debounce増加 | 連続ナビゲーション時の計算回数削減 |
| auto_refresh throttle | 編集中の計算頻度削減 |
| 差分キャッシュ | ファイル切替時の再計算スキップ |
| 大ファイル警告 | ユーザーへの事前通知 |

### Phase 3: git操作キャッシュ

根本原因: mutable revision (`:0`) のキャッシュバイパスにより `git show :0:<path>` がファイル選択のたびに実行、`git rev-parse --verify HEAD` も毎回実行されていた。

1. **mutable revision の generation-based キャッシュ** (Patch 1)
   - `git.get_file_content` をラップし、`:0` 等のmutable revisionにもキャッシュを適用
   - `mutable_generation` カウンタで無効化を制御
   - staging操作 (`gs`/`gr`/`gu`/`-`/`S`/`U`/`X`) 時のみインクリメント

2. **resolve_revision の結果キャッシュ** (Patch 2)
   - `git.resolve_revision` をラップし、`git rev-parse --verify HEAD` の結果をキャッシュ
   - `cc`/`ca` (commit) 時のみ無効化

3. **refresh_diff_view の150ms delay削除** (Patch 3)
   - `vim.defer_fn(..., 150)` → `vim.schedule` に変更
   - gitsignsのstage_hunkは同期的にgit indexを更新するため待機不要

4. **hunk_counts の generation-based スキップ** (Patch 4)
   - `fetch_and_render()` に `mutable_generation` チェックを追加
   - staging操作がない限り `git diff -U0` x2 をスキップ

## 効果

| 最適化項目 | 効果 |
|------------|------|
| debounce増加 | 連続ナビゲーション時の計算回数削減 |
| auto_refresh throttle | 編集中の計算頻度削減 |
| 差分キャッシュ | ファイル切替時の再計算スキップ |
| 大ファイル警告 | ユーザーへの事前通知 |
| mutable revision cache | ファイル選択時の `git show` スキップ |
| resolve_revision cache | ファイル選択時の `git rev-parse` スキップ |
| 150ms delay削除 | staging操作後の体感遅延除去 |
| hunk_counts skip | staging以外のrefreshで `git diff -U0` x2 スキップ |

## 削除条件

- codediff.nvim upstreamでパフォーマンス改善（extmarkバッチ処理、UTF-16変換キャッシュ等）が実装されたら削除を検討
- 参考: upstreamへのIssue/PR作成を推奨
