# Claude Code + Neovim 連携

Claude Code CLI と Neovim の双方向連携。claudecode.nvim（ACP protocol）で Neovim のエディタ状態を Claude Code に共有し、tmux-mcp で隣接ペインの出力を取得する。

## コンポーネント

| コンポーネント | 役割 |
|---|---|
| claudecode.nvim | Neovim <-> Claude Code CLI ブリッジ（WebSocket/ACP） |
| tmux-mcp | tmux ペイン内容を Claude Code に提供する MCP サーバー |

## claudecode.nvim

### 概要

Claude Code CLI が Neovim のエディタ状態（開いているファイル、カーソル位置、選択範囲）を自動認識するプラグイン。Neovim 内の snacks.nvim ターミナルで Claude Code を起動し、双方向に連携する。

設定: `common/nvim/.config/nvim/lua/plugins/claudecode.lua`

### キーバインド

| キー | モード | 動作 |
|---|---|---|
| `<C-,>` | n, t | Claude Code ターミナルトグル |
| `<leader>Cs` | v | ビジュアル選択を Claude Code に送信 |
| `<leader>Cb` | n | 現在のバッファを Claude Code に追加 |

### 提供機能

- Claude Code が現在のバッファ、カーソル位置、選択範囲を自動認識
- Claude Code の変更提案を Neovim 内 diff で表示 -> accept/reject
- ビジュアル選択をプロンプトに直接送信
- `:ClaudeCodeDiffAccept` / `:ClaudeCodeDiffDeny` で diff 操作

### ターミナル表示

- 右 split、幅 35%
- snacks.nvim のターミナルプロバイダーを使用
- `<C-,>` でトグル（normal/terminal モード両方で動作）

## tmux-mcp

### 概要

Claude Code が tmux のペイン内容を読み取れる MCP サーバー。サーバ出力、テスト結果、ログなど隣接ペインの表示内容を Claude Code のコンテキストとして利用できる。

### 登録

```bash
claude mcp add --scope user tmux -- npx -y tmux-mcp
```

ユーザースコープで `~/.claude.json` に登録済み。dotfiles 内のファイル変更は不要。

### 主要ツール

| ツール | 動作 |
|---|---|
| `capture-pane` | ペインの表示内容をキャプチャ |
| `list-sessions` | tmux セッション一覧 |
| `list-windows` | ウィンドウ一覧 |
| `list-panes` | ペイン一覧 |
| `execute-command` | tmux コマンド実行 |
| `get-command-result` | コマンド結果の取得 |

## avante.nvim との使い分け

| | avante.nvim | claudecode.nvim |
|---|---|---|
| 接続先 | Claude API 直接 | Claude Code CLI |
| UI | Neovim 内チャットサイドバー | Neovim 内ターミナル split |
| 用途 | 軽い質問、単一ファイル編集 | 複数ファイル実装、デバッグ |
| キーマップ | `<leader>a*` | `<C-,>`, `<leader>C*` |
| ツール利用 | なし | Bash, Read, Edit, MCP 等 |
| コンテキスト | 手動選択 | 自動認識 + tmux ペイン |

## ワークフロー例

### エラーデバッグ

1. Neovim でエラーが発生しているファイルを開く
2. `<C-,>` で Claude Code を起動
3. エラー箇所をビジュアル選択 -> `<leader>Cs` で送信
4. Claude Code がバッファ内容 + LSP 診断を認識してデバッグ

### サーバ出力を見ながらデバッグ

1. tmux の左ペインに Neovim、右上ペインにサーバ出力を表示
2. Neovim 内で `<C-,>` → Claude Code を起動
3. Claude Code に「隣のペインのエラーログを見て原因を特定して」と指示
4. tmux-mcp が自動でペイン内容をキャプチャし、コードと合わせて分析

### テスト失敗の修正

1. tmux ペインでテストを実行、失敗を確認
2. Neovim で `<C-,>` → Claude Code を起動
3. `<leader>Cb` でテスト対象ファイルを追加
4. 「tmux ペインのテスト結果を見て修正して」と指示
5. Claude Code が diff を提示 → Neovim 内で accept/reject

### Neovim 遠隔デバッグ（tmux 経由）

Claude Code は Neovim の画面を直接見ることができない。tmux コマンドで Neovim を遠隔操作し、内部状態をファイルにダンプすることで、プラグインの不具合やレイアウト問題を調査できる。

前提: Claude Code と Neovim が同一 tmux セッション内の別ペインで動作していること。

#### ペイン特定

```bash
# Neovim が動いているペインを確認
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_width}x#{pane_height}'
# 例: 0:1.1 nvim 422x56
```

以降の例では Neovim ペインを `0:1.1` とする。

#### 画面キャプチャ

```bash
# 現在の表示内容を取得
tmux capture-pane -t 0:1.1 -p

# 先頭/末尾のみ
tmux capture-pane -t 0:1.1 -p | head -20
tmux capture-pane -t 0:1.1 -p | tail -5
```

#### キー送信

```bash
# Normal モードのコマンド
tmux send-keys -t 0:1.1 ':tabonly | enew | only' Enter

# Leader キー（スペースの場合）
tmux send-keys -t 0:1.1 ' gd'

# INSERT モードから抜ける
tmux send-keys -t 0:1.1 Escape
```

注意: INSERT モードや入力待ち状態だとキーが意図通り処理されない。先に `Escape` を送ること。

#### 内部状態ダンプ

Neovim の `:lua` コマンドでウィンドウ/バッファ/タブの状態をファイルに書き出し、Claude Code 側で読む。

```bash
# 全タブとウィンドウ数の一覧
tmux send-keys -t 0:1.1 ':lua local tabs=vim.api.nvim_list_tabpages(); local lines={"tabs="..#tabs}; for i,t in ipairs(tabs) do local wins=vim.api.nvim_tabpage_list_wins(t); local cur=vim.api.nvim_get_current_tabpage()==t and " *" or ""; table.insert(lines, string.format("  [%d] id=%d wins=%d%s", i, t, #wins, cur)) end; vim.fn.writefile(lines, "/tmp/nvim_state.log")' Enter
cat /tmp/nvim_state.log

# 現在のタブのウィンドウ詳細（filetype, buffer name, サイズ）
tmux send-keys -t 0:1.1 ':lua local t=vim.api.nvim_get_current_tabpage(); local wins=vim.api.nvim_tabpage_list_wins(t); local lines={}; for i,w in ipairs(wins) do local b=vim.api.nvim_win_get_buf(w); table.insert(lines, string.format("w%d buf=%d ft=%s %dx%d %s", i, b, vim.bo[b].filetype, vim.api.nvim_win_get_width(w), vim.api.nvim_win_get_height(w), vim.api.nvim_buf_get_name(b))) end; vim.fn.writefile(lines, "/tmp/nvim_state.log")' Enter
cat /tmp/nvim_state.log
```

#### モンキーパッチによるトレース

プラグイン関数の呼び出しをトレースするには、config 内でラッパー関数を差し込み、引数やコールスタックをファイルに書き出す。

```lua
-- config() 内に追記
local target_mod = require("some.plugin.module")
local orig_fn = target_mod.some_function
target_mod.some_function = function(...)
  local info = debug.getinfo(2, "Sl")
  local f = io.open("/tmp/trace.log", "a")
  if f then
    f:write(string.format("[%s] some_function called from %s:%s\n",
      os.date("%H:%M:%S"), info.short_src, tostring(info.currentline)))
    f:close()
  end
  return orig_fn(...)
end
```

注意: `vim.fn.writefile` は async コールバック内で使えない場合がある。`io.open` を使うこと。

#### 典型的なデバッグフロー

1. `tmux capture-pane` で現象を確認（レイアウト崩れ、不要なウィンドウ等）
2. `:lua` ダンプでウィンドウ構成・filetype・buffer name を特定
3. 必要に応じてモンキーパッチでトレースを仕込み、nvim を再起動
4. `tmux send-keys` で操作を再現し、トレースログとキャプチャで原因を特定
5. 修正後、デバッグコードを除去

## 既存機能との関係

| 機能 | 関係 |
|---|---|
| file watcher (autocmds.lua) | Claude Code が書き込んだファイルの自動リロードに対応済み |
| codediff.nvim | Claude Code の diff accept 後、git diff レビューに利用 |
| tmux claude-hooks | ステータスバッジは独立機能。Claude Code の状態通知に使用 |
