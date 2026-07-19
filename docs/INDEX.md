# ドキュメント一覧

`README.md` は概要と導入入口、このファイルは詳細文書の目録を担当する。

## インストール

- [インストールガイド](install/index.md) — 全環境共通の入口と実行順
- [No-Sudo Install Mode](install/install-no-sudo.md) — sudoなしLinux固有の構成と制約
- [新環境セットアップ](install/setup-new-environment.md) — 環境別レシピと新ツールの登録先

## ツール

- [Neovim](tools/neovim/overview.md)
  - [トラブルシューティング](troubleshooting/neovim.md)
  - [ローカルパッチ一覧](tools/neovim/patches/README.md)
- [tmux](tools/tmux.md)
- [sesh](tools/sesh.md)
- [Starship](tools/starship.md)
- [Ghostty](tools/ghostty.md)
- [Clipboard](tools/clipboard.md)
- [Zsh non-interactive guard](tools/zsh-non-interactive-guard.md)
- [Zsh起動最適化](tools/zsh-startup-optimization.md)

## AIエージェント

- [tmux agent状態管理仕様](specs/agent-stop-notification.md)

### pi

- [概要](ai-agents/pi/overview.md)
- [Agent delegation](ai-agents/pi/agent-delegation.md)
- [共有設定レイヤー](ai-agents/pi/agent-layer.md)
- [MCPレイヤー](ai-agents/pi/mcp-layer.md)
- [Memoryレイヤー](ai-agents/pi/memory.md)
- [Web Researchレイヤー](ai-agents/pi/web-research.md)

### Claude Code

- [開発ワークフロー](ai-agents/claude/claude-development.md)
- [APIフォールバック](ai-agents/claude/claude-fallback.md)
- [スキル](ai-agents/claude/claude-skills.md)
- [Beacon連携](ai-agents/claude/claude-beacon.md)
- [Neovim連携](ai-agents/claude/claude-neovim.md)
- [ccusage](ai-agents/claude/ccusage.md)

### その他

- [Command Code](ai-agents/commandcode/overview.md)
- [Cursor Agent CLI](ai-agents/cursor/overview.md)
- [Ralph](ai-agents/ralph/overview.md)
  - [Crew orchestration](ai-agents/ralph/crew.md)
  - [Schedule](ai-agents/ralph/schedule.md)

## インフラストラクチャ

- [rcon](infrastructure/rcon.md) — リモート接続の動作原理
- [rconセットアップ](infrastructure/rcon-setup.md) — ターゲット追加手順
- [tmux server再起動](infrastructure/tmux-server-restart.md)
- [dotfiles同期](infrastructure/dotfiles-sync.md)
- [開発gateway](infrastructure/dev-gateway.md)
- [開発tunnel](infrastructure/dev-tunnel.md)
- [Database](infrastructure/database.md)

## 設定

- [Git](configuration/git-config.md)
- [1Password](configuration/1password-integration.md)
- [Modern CLI Tools](configuration/modern-cli-tools.md)
- [AeroSpace + SketchyBar](configuration/sketchybar-aerospace.md)

## トラブルシューティング

- [Neovim](troubleshooting/neovim.md)
- [Powerline Unicode](troubleshooting/powerline-unicode.md)

## レビュー記録

レビューは記載時点のスナップショットであり、現行仕様ではない。

- [pi harness review](reviews/pi-harness-review.md)
