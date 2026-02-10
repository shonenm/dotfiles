# codediff.nvim: パフォーマンス最適化

- **ファイル**: `common/nvim/.config/nvim/lua/plugins/codediff.lua`
- **対象**: `esmuellert/codediff.nvim`
- **症状**: 大きなファイルや連続操作時に差分計算が遅延し、UIがもたつく
- **原因**: Lua側の処理が律速（UTF-16変換、extmark適用、auto_refreshの頻繁な発火）

## 実装した最適化

### Phase 1: 設定レベル

1. **debounce値の調整** (400ms → 600ms)
   - `keymaps.setup`内の`debounce_ms`を600msに増加
   - 連続でj/k操作した際の差分計算回数を約25%削減

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

## 削除条件

- codediff.nvim upstreamでパフォーマンス改善（extmarkバッチ処理、UTF-16変換キャッシュ等）が実装されたら削除を検討
- 参考: upstreamへのIssue/PR作成を推奨
