# tmux

TokyoNight Night テーマ + 透過背景。Ghostty / Neovim 統合対応。

## 基本設定

| 設定 | 値 | 備考 |
|------|-----|------|
| Prefix | `Ctrl+Space` | デフォルト `Ctrl+b` から変更 |
| Default command | `${SHELL}` | non-login shell（pane 起動高速化） |
| Mouse | ON | ドラッグ選択、スクロール対応 |
| Clipboard | OSC52 | SSH 経由でもコピー可能 |
| Focus events | ON | Neovim autoread 等に必要 |
| History limit | 50000 | スクロールバック行数 |
| Passthrough | ON | Kitty graphics protocol（image.nvim 等） |
| Extended keys | ON | CSI u モード（`C-S-u` 等の修飾キーを Neovim に送信） |
| Base index | 1 | Window/Pane 番号が 1 から開始 |
| Escape time | 0 | ESC 遅延なし（Neovim 対応） |
| Renumber | ON | Window 削除時に自動採番 |
| Activity | ON | 非アクティブ Window の変更を検知 |
| Terminal title | `#{b:pane_current_path}` | aerospace ウィンドウ検出用 |
| Status interval | 5秒 | ステータスバー更新間隔（遅延対策） |

## キーバインド

全て `prefix` 付き（特記がない限り）。

### which-key メニュー

`prefix + Space` で which-key スタイルのキーバインドヘルプをポップアップ表示。nvim の which-key.nvim と同じ UX。

| キー | 動作 |
|------|------|
| `Space` | メニュー表示 |
| `p` | +Pane サブメニュー（分割、リサイズ、タイトル、sync）|
| `w` | +Window サブメニュー（作成、移動、削除）|
| `s` | +Session サブメニュー（切り替え、リネーム）|
| `o` | +Popup サブメニュー（lazygit, gh-dash 等）|

よく使うショートカットはトップレベルにも配置（`|`, `-`, `g`, `G`, `j`, `f`, `F`, `v`, `r`, `?`）。

### Pane / Window 操作

| キー | 動作 |
|------|------|
| `\|` | 水平分割（カレントパス維持） |
| `-` | 垂直分割（カレントパス維持） |
| `C-h/j/k/l` | Pane 移動（**prefix 不要**、vim-tmux-navigator） |
| `H/J/K/L` | Pane リサイズ（5 セル、リピート可） |
| `n / p` | 次/前 Window（リピート可、1 秒） |
| `C-l / C-h` | 次/前 Window（prefix 付き、プラグイン上書き） |
| `W` | Pane 入れ替え（番号指定、`prefix q` で確認） |
| `t` | Pane タイトル設定 |
| `T` | Window リネーム |
| `X` | Window 削除（確認あり） |
| `r` | 設定リロード |
| `S` | SYNC モード切替 |
| `F12` | ネストセッション切替（**prefix 不要**） |

### Session 操作

| キー | 動作 |
|------|------|
| `s` | セッショングループ二段 picker（グループ menu → グループ内 choose-tree。グループ未使用時は従来のフラットな choose-tree） |
| `C-g` | 現 session のグループ設定/解除（fzf popup、後述の Session グループ参照） |
| `Tab` | 直前のセッションへトグル切替（`switch-client -l`、sesh 非依存） |
| `L` | 直前のセッションへ（`sesh last`、picker 履歴を参照） |
| `9` | 親プロジェクト session へジャンプ（`sesh connect --root`、worktree 等のネストから復帰） |
| `(` | 前のセッション（名前順、リピート可） |
| `)` | 次のセッション（名前順、リピート可） |
| `f` | 色付きセッション picker（既存 tmux session のみ、`tmux-session-color.sh`）|
| `C-f` | sesh picker（多段フィルタ: `^a` all / `^t` tmux / `^g` config / `^x` zoxide / `^f` find / `^d` kill）|

prefix 不要のグループ移動キー（root table）:

| キー | 動作 |
|------|------|
| `M-h` / `M-l` (`C-M-h` / `C-M-l`) | 同グループ内の前/次 session へ（名前順・循環） |
| `M-j` / `M-k` (`C-M-j` / `C-M-k`) | 次/前のグループで最後に見ていた session へ（未記録なら先頭、ungrouped は末尾の 1 バケツ扱い・循環） |

ローカル macOS では aerospace が `alt-hjkl` / `alt-shift-hjkl` をウィンドウ操作で
グローバルに掴んでいるため、`C-M-hjkl`（Ctrl+Option+hjkl）を使う。aerospace の
いない環境（リモート Linux 等）では `M-hjkl` がそのまま届く。

`choose-tree` と `( / )` は共に名前順で巡回するため、後述の命名規約 (`rcon-*`, `proj-*`, `pers-*`, `ops-*`) に従うとカテゴリ単位で束ねて見える／辿れる。`prefix f` と `prefix C-f` の使い分けは [sesh.md](./sesh.md) 参照。

### Floating Window (display-popup)

| キー | 動作 | サイズ |
|------|------|--------|
| `g` | lazygit（カレントパスで起動） | 80% × 80% |
| `k` | keifu（Git コミットグラフ TUI） | 80% × 80% |
| `Q` | quay（TUI ポートマネージャー） | 80% × 80% |
| `G` | gh-dash（GitHub Dashboard） | 85% × 85% |
| `P` | pgcli（PostgreSQL クライアント） | 80% × 80% |
| `j` | Scratchpad シェル（永続 `scratch` セッション、トグル） | 80% × 80% |
| `f` | セッション切り替え（fzf + プレビュー） | 60% × 60% |
| `F` | ghq プロジェクト切り替え（fzf） | 60% × 60% |

- `-E` フラグにより、コマンド終了時に popup 自動クローズ
- `d` の pgcli は `$DATABASE_URL` 環境変数があれば使用、なければ `postgresql://postgres:postgres@localhost:5432/postgres` にフォールバック
- `G` の gh-dash は 85% サイズ（列が多いため lazygit より少し大きめ）
- `j` の Scratchpad は永続セッション (`scratch`) を使用。再度 `prefix + j` でトグル（セッション状態を維持）
- `f` はデフォルトの `find-window` を上書き
- `F` はプロジェクト名でセッションを作成（既存なら切り替え）。プロジェクトルートに `.tmux` ファイルがあれば新規セッション時に自動実行

### Copy Mode (vi スタイル)

| キー | 動作 |
|------|------|
| `prefix + v` | Copy Mode に入る |
| `prefix + u` / `prefix + C-u` | Copy Mode に入り即スクロールアップ |
| `v` | 選択開始 |
| `Ctrl+v` | 矩形選択切替 |
| `y` | コピー（OSC52 経由でクリップボードへ） |
| `Enter` / `Esc` | キャンセル |
| `Ctrl+u` / `Ctrl+d` | 4 行スクロール |
| `u` / `d` | 半ページスクロール（倍速移動） |
| マウスドラッグ | 自動コピー → OSC52（Copy Mode 終了） |

## ステータスバー

位置: 上部（`status-position top`）、透過背景。

```
 Session   1 zsh  2 nvim   CPU 12% | RAM 45% | GPU 8% | SSD 82%   MODE   branch  01/30 15:00   host
```

### 右側セグメント

| セグメント | アイコン | 色 | 内容 |
|------------|----------|-----|------|
| CPU |  | 閾値別（緑/黄/赤） | CPU 使用率（macOS: iostat / Linux: /proc/stat） |
| RAM |  | 閾値別（緑/黄/赤） | メモリ使用率（macOS: vm_stat / Linux: /proc/meminfo） |
| GPU |  | 閾値別（緑/黄/赤） | GPU 使用率（macOS: macmon / Linux: nvidia-smi） |
| Storage |  | 閾値別（紫/黄/赤） | ディスク使用率（80% 以上で表示） |
| モード | なし | モード別 | OFF / COPY / SYNC / PREFIX / NORMAL |
| Git status |  | 緑 `#9ece6a` | ブランチ名 + ahead/behind (`⇡N⇣M`) + 差分統計 (`Nf +A/-D`、HEAD と working tree 比較) |
| 日時 |  | 青 `#7aa2f7` | `MM/DD HH:MM` |
| ホスト |  | 水色 `#7dcfff` | ホスト名（太字） |

### システム統計の閾値

| メトリクス | 低 (緑) | 中 (黄) | 高 (赤) |
|------------|---------|---------|---------|
| CPU | < 50% | 50-79% | ≥ 80% |
| RAM | < 70% | 70-89% | ≥ 90% |
| GPU | < 50% | 50-79% | ≥ 80% |
| Storage | 80-89% (紫) | 90-94% (黄) | ≥ 95% (赤) |

### モード表示

優先度: OFF > RELOAD > THUMBS > COPY > SYNC > ZOOM > NORMAL

| モード | 色 | 条件 |
|--------|-----|------|
| OFF | グレー `#545c7e` | ネストセッション（外側無効） |
| RELOAD | オレンジ `#ff9e64` | 設定リロード中 |
| THUMBS | エメラルド `#41a6b5` | tmux-thumbs 操作中 |
| COPY | 赤 `#f7768e` | Copy Mode 中 |
| SYNC | ティール `#73daca` | Pane 同期中 |
| ZOOM | 紫 `#bb9af7` | Pane ズーム中（`ZOOM 1/3` 形式でペイン番号/総数を表示） |
| NORMAL | 青 `#7aa2f7` | 通常 |

### Prefix ヘルプ表示

Prefix (`Ctrl+Space`) 押下時、ステータスバー右側全体がキーバインドヘルプに切り替わる。

```
  -| split  g git  G gh  k keifu  j scratch  f sess  F proj  v copy  r reload  ? keys  Space menu
```

| キー | 動作 |
|------|------|
| `-` | 垂直分割 |
| `\|` | 水平分割 |
| `g` | lazygit popup |
| `G` | gh-dash popup |
| `k` | keifu popup（Git コミットグラフ） |
| `j` | Scratchpad シェル |
| `f` | セッション切り替え |
| `F` | ghq プロジェクト切り替え |
| `A` | pane レイアウトプリセット menu（保存/適用） |
| `N` | smug session テンプレート起動 |
| `v` | Copy Mode |
| `r` | 設定リロード |
| `?` | キーバインド一覧 |
| `Space` | which-key メニュー |

次のキー入力で通常表示に戻る。

### Window タブ

- 非アクティブ: グレー背景 `#3b4261` + 角丸
- アクティブ: セッション固有のアクセントカラー + 太字 + 角丸（後述「Per-session アクセントカラー」参照）
- Claude 通知バッジ: オレンジ `#ff6600` で件数表示（後述）

## ビジュアル設定

### Pane 枠線

- **スタイル**: 二重線（`pane-border-lines double`）
- **上部ラベル**: `ペイン番号: タイトル or コマンド名`
- **インジケーター**: 矢印 + 色の両方（`both`）

### Pane 枠線のモード色

| 条件 | 枠色 |
|------|------|
| OFF | グレー `#545c7e` |
| RELOAD | オレンジ `#ff9e64` |
| THUMBS | エメラルド `#41a6b5` |
| Copy Mode | 赤 `#f7768e` |
| SYNC | ティール `#73daca` |
| PREFIX | 黄 `#ffea00` |
| ZOOM | 紫 `#bb9af7` |
| 通常 | 青 `#7aa2f7` |

### 透過設定

- 非アクティブ Pane: 文字を暗く（`fg=colour244`）、背景透過
- アクティブ Pane: 文字を明るく（`fg=colour255`）、背景透過
- ステータスバー: `bg=default`（Tmux 3.2+ 対応）

### Terminal 互換性

- **RGB**: `xterm-256color:RGB` で True Color 対応
- **Undercurl**: `Smulx` + `Setulc` オーバーライドで波線下線対応
- `$TERM` / `$TERM_PROGRAM` を環境変数として更新

## vim-tmux-navigator

`C-h/j/k/l` で Neovim ⇔ tmux Pane 間をシームレスに移動。prefix 不要。

Neovim 側にも `christoomey/vim-tmux-navigator` プラグインが必要。

## SYNC モード

`prefix + S` で全 Pane に同じ入力を送信。複数サーバーの同時操作に便利。

有効時:
- ステータスバーに `SYNC` 表示（ティール）
- Pane 枠線がティールに変化
- テキストが明るくなる（`fg=colour255`）

## Pane レイアウトプリセット (`prefix + A`)

ウィンドウの pane 構成（分割構造 + サイズ比）を名前付きで保存し、pane を生成/破棄せず resize だけで復元する。`scripts/tmux-layout`（Python）が実体。

- 保存/適用は `prefix + A` の fzf popup から（`<save current layout as...>` で保存、選択で適用）
- マッチングは topology 署名（分割構造）で行うため、ウィンドウサイズが違っても同一構造なら適用可能
- プリセットは `~/.local/share/tmux-layout/*.layout`。サイズ非依存（比率保存）なので **dotfiles 経由で全環境に同期される**（`common/tmux/.local/share/tmux-layout/` を stow）

### 切替時の自動リサイズ

`tmux-layout apply` 実行時、そのウィンドウに `@layout-preset` オプションが記録される。以降:

- `pane-focus-in`（window 切替）と `client-session-changed`（session 切替）の hook が `tmux-layout autoapply` を実行
- 記録されたプリセットがあれば、ドリフトした構成を保存値へ自動スナップ
- プリセット未設定のウィンドウは即 return = ゼロコスト（非フリッカー）

```bash
tmux-layout list            # プリセット一覧（topology 署名付き）
tmux-layout save <name>     # 現ウィンドウ構成を保存
tmux-layout apply <name>    # 適用 + @layout-preset 記録
```

## Session テンプレート (`prefix + N` / smug)

[smug](https://github.com/ivaaaan/smug) で「claude / nvim / shell などを配置済みの session」を 1 コマンドで起動する。テンプレートは YAML で宣言し `common/smug/.config/smug/*.yml`（stow 同期）に置く。

- `prefix + N` の popup でテンプレートを選び `smug start <name> -d` → `switch-client` で起動
- 各 pane に起動コマンド（claude, nvim 等）を宣言。`layout` で named レイアウト（main-vertical 等）を指定
- 正確な保存幾何に合わせたい場合は、window の `commands` で `tmux set-window-option @layout-preset <name>` を設定。topology が一致すれば attach 時に autoapply hook が正確にスナップする
- 例: `common/smug/.config/smug/dev.yml`

## ネストセッション (F12)

SSH 先の remote tmux を local tmux 内で使う場合、`F12` で外側 tmux のキーバインドを一括 OFF にする。

- `F12` 押下 → prefix 無効化、全キーストロークが内側 tmux にパススルー
- `F12` 再押下 → 外側 tmux のキーバインド復帰

OFF 中の視覚的変化:
- ステータスバーがグレーアウト（`fg=#545c7e, bg=#1a1b26`）
- モード表示が `OFF`（グレー `#545c7e`）
- Window タブがグレー一色

参考: [samoshkin/tmux-config](https://github.com/samoshkin/tmux-config)

## Session 命名規約

セッションが増えた際に `choose-tree -O name` と `switch-client -p/-n` がカテゴリ単位で束ねて見える／辿れるようにするための規約。tmux 本体に session tag / group の概念はないため、名前のプレフィックスでグルーピングを表現する。

| プレフィックス | 用途 | 例 |
|---------------|------|-----|
| `rcon-` | `rcon host[:container]` で起動したリモート/コンテナ作業 | `rcon-ailab-myproject-dev`、`rcon-prod1` |
| `proj-` | ローカルのプロジェクト作業 | `proj-myproject-api`、`proj-growth` |
| `pers-` | dotfiles / 雑務 / 個人メモ | `pers-dotfiles`、`pers-notes` |
| `ops-` | 監視・運用・インシデント対応 | `ops-grafana`、`ops-oncall` |

プレフィックスがアルファベット順で並ぶため、`prefix s` の choose-tree でも `prefix+( / )` の巡回でも近い用途のセッションが隣接する。rcon 由来のセッション名は既に `host-container` 形式で sanitize されているため `rcon-` プレフィックスを足すだけで整合する。

固定セッション（`scratch`、`MAIN`）はプレフィックスなしで運用しても構わないが、choose-tree ではリスト末尾にまとめて並ぶ（大文字 → 小文字、プレフィックスあり → なしの順で分かれる）。

## Session グループ (`@group`)

名前規約に依存しない明示的なセッショングループ。各 session の `@group` user option
(session-scoped) を唯一の真実とし、session 名は自由に付けられる。実装は
`scripts/tmux-session-group.sh`。

- 設定: `prefix C-g` の fzf popup で既存グループ選択 / 新規入力 / `(none)` で解除。
  CLI からは `tmux-session-group.sh set <group> [session]`（グループ名は `A-Za-z0-9_-` のみ）
- 移動: `M-h/l` で同グループ内、`M-j/k` でグループ間（前述のキー表参照）
- 一覧: `prefix s` がグループ menu → 選択グループのみの choose-tree という二段 picker になる。
  menu の `u` で ungrouped、`a` で全 session のフラット表示
- 永続化: user option は tmux server 再起動で消え resurrect も復元しないため、
  `$XDG_STATE_HOME/tmux/session-groups`（`session名<TAB>group`）に同期し、
  session-created hook / config load で再適用する。死んだ session のエントリは
  保持され、同名 session の再作成（resurrect 復元含む）時に自動でグループが戻る

worktree 毎に session を切る運用では、session 作成側で
`tmux-session-group.sh set <repo名> <session名>` を呼べば同一プロジェクトの
worktree 群が 1 グループにまとまる。

## Per-session アクセントカラー

セッション名のハッシュから自動的にアクセントカラーを決定し、セッション名バッジとアクティブ Window タブに適用。複数セッションを同時に開いた際の視認性を向上させる。

### カラーパレット（TokyoNight 準拠）

| 色 | Hex |
|-----|-----|
| Red/Pink | `#f7768e` |
| Orange | `#ff9e64` |
| Yellow | `#e0af68` |
| Green | `#9ece6a` |
| Teal | `#73daca` |
| Blue | `#7aa2f7` |
| Purple | `#bb9af7` |
| Cyan | `#7dcfff` |

### 仕組み

1. `session-created` Hook で `tmux-session-color.sh apply` を実行
2. セッション名を `cksum` でハッシュ化し、8 色から 1 色を決定
3. `@session_color` にセッション固有の色を保存
4. `status-left`（セッション名バッジ）と `window-status-current-format`（アクティブ Window タブ）を per-session で設定
5. `client-session-changed` / `client-attached` Hook で `refresh` を実行し、色を再適用

per-session 設定により、複数 Ghostty ウィンドウで異なるセッションを開いても各セッション固有の色が維持される。

### セッション切り替え

`prefix + f` で fzf ベースのセッション切り替え。各セッション名がアクセントカラーで ANSI 着色表示される。

## Claude Code 通知統合

tmux ステータスバーに Claude Code の状態を通知バッジとして表示。

### 仕組み

1. Claude Code が `${DOTFILES_SHARED_DIR:-$HOME/.cache}/claude/status/workspace_*.json` にステータスを書き込む
2. `tmux-claude-badge.sh` がウィンドウごとの通知件数を角丸バッジで表示
3. `tmux-claude-focus.sh` がウィンドウ切替時に 5 秒タイマーで通知を自動消去

### バッジ表示

- 通知あり: オレンジ背景 `#ff6600` に件数（白太字）
- アクティブ Window: 暗めオレンジ `#cc5500`（目立ちすぎ防止）
- 対象ステータス: `idle` / `permission` / `complete`

### Hook

```
session-window-changed → tmux-claude-focus.sh
client-session-changed → tmux-claude-focus.sh
```

## ステータスバー最適化

リモートコンテナ環境でのキー入力遅延を防ぐため、以下の最適化を実施:

| 設定 | 値 | 備考 |
|------|-----|------|
| status-interval | 5秒 | 更新頻度を抑制（SSH環境での遅延対策） |
| history-limit | 10000 | スクロールバック行数（大量履歴による遅延対策） |
| スクリプトキャッシュ | 3秒 | CPU/RAM/GPU/Storage/Git branch すべてにキャッシュ適用 |
| キャッシュ場所 | `${XDG_CACHE_HOME:-$HOME/.cache}/tmux/sysstat/` | XDG キャッシュに統一 |

キャッシュにより、status-interval (10秒) ごとの更新時にスクリプトが実行されても、3秒以内の再呼び出しはキャッシュから返却される。

## テーマ再生成

Powerline 文字が表示されない場合:

```bash
scripts/regenerate-tmux-theme.sh
tmux source ~/.config/tmux/tmux.conf
```

Linux 環境では `install.sh` 実行時に自動で再生成される。

**重要**: `tokyonight.tmux` を直接編集せず、`regenerate-tmux-theme.sh` を編集して再生成すること。Powerline 文字が git 操作で破損する可能性があるため。

## ファイル構成

```
common/tmux/.config/tmux/
├── tmux.conf          # メイン設定
├── tokyonight.tmux    # テーマ（生成ファイル）
├── claude-hooks.tmux  # Claude 通知 Hook
└── plugins/tmux-which-key/
    └── config.yaml    # which-key メニュー設定

scripts/
├── regenerate-tmux-theme.sh  # テーマ再生成
├── tmux-utils.sh             # 共通ユーティリティ（get_mtime: クロスプラットフォーム対応）
├── tmux-cpu.sh               # CPU 使用率取得（macOS: iostat / Linux: /proc/stat、3秒キャッシュ）
├── tmux-ram.sh               # RAM 使用率取得（macOS: vm_stat / Linux: /proc/meminfo、3秒キャッシュ）
├── tmux-gpu.sh               # GPU 使用率取得（macmon / nvidia-smi、3秒キャッシュ）
├── tmux-storage.sh           # ストレージ使用率取得（閾値超過時のみ表示、3秒キャッシュ）
├── tmux-git-branch.sh        # Git ブランチ名取得（パスごとに3秒キャッシュ、単独利用）
├── tmux-git-status.sh        # Git ブランチ + ahead/behind(⇡⇣) + 差分統計(Nf +A/-D)（5秒キャッシュ、status-right 用）
├── tmux-claude-badge.sh      # 通知バッジ表示
├── tmux-claude-focus.sh      # 通知自動消去
├── tmux-session-color.sh     # Per-session アクセントカラー（apply / refresh / fzf-sessions）
├── tmux-popup-ghq.sh         # ghq プロジェクト切り替え（popup 用）
├── tmux-sync-toggle.sh       # SYNC モード切替（which-key から呼び出し）
├── tmux-zoom-toggle.sh       # ZOOM モード切替（which-key から呼び出し）
├── tmux-layout              # pane レイアウトプリセット管理（save/apply/autoapply/menu）
├── tmux-layout-menu.sh       # レイアウトプリセット fzf popup（prefix + A）
├── tmux-smug-menu.sh         # smug session テンプレート起動 popup（prefix + N）
└── tmux-thumbs-wrapper.sh    # tmux-thumbs カスタムラッパー（Rust ラッパー問題回避）
```

## プラグイン (TPM)

| プラグイン | 用途 |
|------------|------|
| vim-tmux-navigator | Neovim ⇔ tmux シームレス移動 |
| tmux-resurrect | セッション保存・復元（Pane 内容含む） |
| tmux-continuum | 自動復元（`@continuum-restore on`） |
| tmux-thumbs | Vimium風ヒントベーステキスト選択（URL、パス、gitハッシュ等を即コピー） |
| tmux-which-key | which-key スタイルのキーバインドヘルプポップアップ |

Resurrect 設定:
- `@resurrect-capture-pane-contents on` — Pane の表示内容も保存
- Neovim セッション復元は resession.nvim が担当（tmux-resurrect の `@resurrect-strategy-nvim` は使用しない）

tmux-thumbs 設定:
- `prefix + e` でヒント表示
- 小文字ヒント (a, b, c...): 選択した文字列を `pbcopy` でクリップボードにコピー
- 大文字ヒント (A, B, C...): URL はブラウザで開き、ファイルパスはエディタ (`$EDITOR` or nvim) で開く
- カスタムラッパー (`tmux-thumbs-wrapper.sh`) を使用。tmux-thumbs 本体の Rust ラッパー (`swapper.rs`) が detached window + swap-pane 方式でキーボード入力を受け付けない問題の回避策として、新しいウィンドウで直接 thumbs を実行する方式に変更

tmux-which-key 設定:
- 設定ファイル: `plugins/tmux-which-key/config.yaml`（dotfiles で管理）
- `tmux.conf` でプラグインディレクトリへシンボリックリンクを自動作成
- TokyoNight テーマに合わせたスタイリング

AI エージェント状態監視（自前スクリプト）:
- `scripts/tmux-agent-status.sh` が `~/.claude/projects/**/*.jsonl` を監視し、各セッションの Claude Code / Codex / Amp の running / done / error 状態を判定
- `scripts/tmux-agent-sidebar.sh` がセッショングループ別のセッション一覧と全エージェント状態を常時表示する pane を管理（現在のグループ/セッションをハイライト）
- サイドバー下部に Claude / Codex / Gemini / Cursor の使用量を表示。Codex は `~/.codex/auth.json` の OAuth token を自動 refresh するが、refresh token invalidated の場合は `codex login` が必要

| キー | 動作 |
|------|------|
| `prefix a` | エージェント状態 popup を開き、選択したペインへジャンプ |
| `prefix b` | AI エージェントサイドバー pane を toggle |
| `prefix R` | watcher 再起動 + 即時スキャン（残留/ハング検出の GC） |

以前使用していた tmux-sensible、tmux-yank、tmux-cpu は削除済み:
- tmux-sensible: 自前設定でカバー（`focus-events`、`history-limit` 等を明示指定）
- tmux-yank: OSC52 (`set-clipboard on`) で代替
- tmux-cpu: カスタムスクリプト (`tmux-cpu.sh`, `tmux-ram.sh`) で代替。Linux で sysstat 不要（`/proc/stat`, `/proc/meminfo` を直接読み取り）
