# Claude Code Development Environment

Claude Code の開発環境設定、カスタムスキル、フック、エージェント、セッション管理ツールのドキュメント。

## Overview

このリポジトリには Claude Code をカスタマイズするための以下の要素が含まれています：

- **Skills** - ユーザーが呼び出せるコマンド（`/d-beacon`, `/d-commit`, `/d-news` 等）
- **Hooks** - Claude の動作に介入する自動処理（Stop, PostToolUse, SessionStart 等）
- **Agents** - Task ツールで起動する専用エージェント（ralph-worker, ralph-reviewer）
- **Rules** - グローバルルール（問題解決、実装方針、コミュニケーション、自律性）
- **Scripts** - セッション管理、ワークツリー管理等のユーティリティ

## File Structure

```
dotfiles/
├── common/claude/.claude/
│   ├── hooks/                      # Claude Code hooks (stow managed)
│   │   ├── ralph-stop-hook.sh      # Ralph loop control (Stop hook)
│   │   ├── ralph-backpressure.sh   # Type check/lint (PostToolUse hook)
│   │   └── ralph-session-context.sh # Project context (SessionStart hook)
│   ├── skills/                     # Claude Code skills (stow managed)
│   │   ├── beacon/SKILL.md         # /beacon - Workspace registration
│   │   ├── commit/SKILL.md         # /commit - Git commit (all, <path> support)
│   │   ├── news/SKILL.md           # /news - Personalized news digest
│   │   ├── update-md/SKILL.md      # /update-md - Documentation update
│   │   ├── ralph/SKILL.md          # /ralph - Autonomous development loop
│   │   ├── ralph-plan/SKILL.md     # /ralph-plan - Interactive planning
│   │   ├── ralph-cancel/SKILL.md   # /ralph-cancel - Loop cancellation
│   │   ├── ralph-resume/SKILL.md   # /ralph-resume - Resume from archive
│   │   ├── ralph-parallel/SKILL.md # /ralph-parallel - Parallel execution
│   │   ├── ralph-collect/SKILL.md  # /ralph-collect - Post-review operations
│   │   └── ralph-cleanup/SKILL.md  # /ralph-cleanup - Worktree cleanup
│   ├── agents/                     # Claude Code agents (stow managed)
│   │   ├── ralph-worker/ralph-worker.md    # Worktree-isolated worker
│   │   └── ralph-reviewer/ralph-reviewer.md # Read-only code reviewer
│   ├── rules/                      # Global rules (stow managed)
│   │   ├── problem-solving.md      # Root cause first, research best practices
│   │   ├── implementation.md       # Scope control, no over-engineering
│   │   ├── communication.md        # Japanese responses, no emoji
│   │   └── autonomy.md             # Confirm before running scripts/push
│   └── news-profile.example.yaml   # /news profile template
├── scripts/
│   ├── cs                          # Session manager (browse, resume, delete)
│   ├── wt                          # Worktree + tmux window manager
│   ├── wt-lib.sh                   # Worktree library (shared by wt and ralph)
│   ├── ralph-lib.sh                # Ralph utilities (permissions setup)
│   ├── ralph-orchestrate           # Parallel worker lifecycle management
│   ├── ralph-crew                  # Persistent worker management
│   ├── ralph-schedule              # Scheduled Claude TUI execution
│   ├── ralph-schedule-exec.sh      # Executor called by launchd/at
│   ├── claude-gc                   # Cleanup all Claude artifacts
│   ├── ai-notify.sh                # Notification script (CLAUDE_CONTEXT support)
│   ├── claude-status.sh            # State management (workspace-based)
│   ├── claude-status-watch.sh      # Remote monitoring (SSH + inotifywait)
│   ├── beacon                      # Manual workspace registration
│   ├── tmux-claude-badge.sh        # tmux badge display
│   └── tmux-claude-focus.sh        # tmux focus processing
├── templates/
│   └── com.user.claude-status-watch.plist  # launchd template
└── docs/
    ├── claude-skills.md            # Skills reference
    ├── claude-development.md       # This documentation
    ├── claude-beacon.md            # Notification system
    ├── claude-neovim.md            # Neovim integration
    ├── claude-fallback.md          # API fallback
    └── ralph.md                    # Ralph autonomous development loop
```

## Settings Configuration

`~/.claude/settings.json` (stow で `common/claude/.claude/settings.json` からシンボリックリンク):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": ["bash -c '$HOME/.claude/hooks/ralph-session-context.sh'"]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": ["~/dotfiles/scripts/ai-notify.sh claude stop"]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": ["~/dotfiles/scripts/ai-notify.sh claude $CLAUDE_NOTIFICATION_TYPE"]
      }
    ]
  }
}
```

**Note**: skill frontmatter で定義された hooks (PreToolUse, PostToolUse, Stop) はグローバルにロードされます。

## Hooks

### SessionStart Hook (`ralph-session-context.sh`)

セッション開始時にプロジェクト情報を収集して `additionalContext` として返します。

**提供情報**:
- プロジェクト構造（tree -L 2）
- Git 情報（ブランチ、最近のコミット、未コミット変更）
- package.json サマリー（scripts, dependencies）
- Supabase 情報（migrations, table names）
- tsconfig.json 設定

**タイムアウト**: 10秒

### Stop Hook (`ralph-stop-hook.sh`)

Ralph ループの継続/終了を制御します。`CLAUDE_SESSION_ID` ベースのセッション固有状態管理。

**動作**:
1. セッションハッシュから `/tmp/ralph/state/active_<hash>` を確認
2. 状態ファイルが存在し phase が `implementation`/`verification` なら継続判定
3. 完了トークン検出、max_iterations 到達、3回連続 stall で終了
4. それ以外は `decision: "block"` で継続

**タイムアウト**: 15秒

### PostToolUse Hook (`ralph-backpressure.sh`)

Edit/Write/MultiEdit 後に自動で型チェック・lint・テスト実行。

**チェック対象**:
- `.ts`/`.tsx` → tsc, eslint, prettier, test
- `.py` → py_compile, ruff
- `.sh` → shellcheck
- `.sql` → supabase db lint
- `.json` → jq 構文検証

**タイムアウト**: 15秒

### PreToolUse Hook (skill frontmatter)

Ralph ループ中に AskUserQuestion や EnterPlanMode をブロック。

```yaml
hooks:
  - event: PreToolUse
    matcher: "AskUserQuestion|EnterPlanMode"
    command: "exit 2"
```

## Agents

### ralph-worker

`isolation: worktree` で定義された並列実行用ワーカーエージェント。

**用途**: `/d-ralph-parallel` で Task ツール経由で起動

**出力フォーマット**:
```
Status: DONE / PARTIAL / BLOCKED
Files changed: ...
Tests: ...
Completion condition: ...
Notes: ...
```

### ralph-reviewer

読み取り専用のコードレビューエージェント（model: sonnet）。

**用途**: 並列実行後のワーカー変更をレビュー

**動作**: ワーカー worktree で `git diff` を実行し、品質・スコープ準拠・タスク完了をチェック

**出力**: APPROVE / REQUEST_CHANGES + 問題リスト

## Rules

グローバルルールは `~/.claude/rules/` に配置され、全セッションに適用されます。

### problem-solving.md

- 対症療法ではなく根本原因を特定して修正
- ワークアラウンド追加前に根本原因を調査
- 不確実な場合は Web 検索で最新のベストプラクティスを調査
- 非推奨の機能や古いパターンを使用しない

### implementation.md

- 指定された範囲のみ実装。勝手な追加・改善は行わない
- スコープ外の変更が必要な場合はユーザーに確認
- 将来のための過剰設計・投機的抽象化は行わない
- 後方互換性のためだけのフォールバック・ワークアラウンドは禁止

### communication.md

- 簡潔な応答・ステータス報告は日本語で行う
- 絵文字を使用しない
- 太字フォーマットを多用しない

### autonomy.md

- テスト・ビルド・デプロイスクリプトはユーザーの確認なく実行しない
- git push はユーザーが明示的に要求しない限り実行しない

**Note**: Ralph ループ内では autonomy.md の一部ルールが上書きされます（テスト・ビルドは自動実行）。

## Session Management (cs)

FZF ベースの Claude Code セッション管理ツール。

### 使い方

```bash
cs              # インタラクティブブラウザを起動
cs --help       # ヘルプ表示
cs --clean      # 30日以上古いセッションを削除
```

### 機能

- セッション一覧表示（最新順ソート）
- FZF でインタラクティブなブラウズ
- プレビューウィンドウで最近のメッセージを表示
- **Enter**: 選択したセッションを `claude --resume` で再開
- **Ctrl-D**: セッション削除（.jsonl ファイル + ディレクトリ）

### データソース

`~/.claude/projects/-<project-path>/*.jsonl`

### セッションデータ構造

各セッションは JSONL 形式で保存：

```json
{"type":"user","message":{"role":"user","content":"..."},"timestamp":"..."}
{"type":"assistant","message":{"role":"assistant","content":[...]},"timestamp":"..."}
```

### 依存

- fzf
- jq

## Creating Custom Skills

スキルは `~/.claude/skills/<skill-name>/SKILL.md` に配置します。

### Frontmatter

```yaml
---
name: my-skill
description: "Short description"
model: sonnet  # optional: sonnet, opus, haiku
hooks:  # optional
  - event: PreToolUse
    matcher: "AskUserQuestion"
    command: "exit 2"
  - event: PostToolUse
    matcher: "Edit|Write"
    command: "~/dotfiles/scripts/my-check.sh"
allowed-tools:  # optional: restrict tools
  - Read
  - Bash
  - Grep
---

# Skill prompt

Instructions for Claude...
```

### Activation

```bash
# Stow でシンボリックリンク作成
cd ~/dotfiles
stow -d common -t ~ claude

# または手動でコピー
cp -r common/claude/.claude/skills/my-skill ~/.claude/skills/
```

### Usage

```
/my-skill [arguments]
```

## Creating Custom Hooks

### Global Hooks (settings.json)

`~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {"matcher": "", "hooks": ["~/my-hook.sh"]}
    ],
    "Stop": [
      {"matcher": "", "hooks": ["~/my-stop-hook.sh"]}
    ]
  }
}
```

### Skill-scoped Hooks (frontmatter)

スキルの SKILL.md frontmatter:

```yaml
hooks:
  - event: PreToolUse
    matcher: "ToolName"
    command: "~/my-pre-hook.sh"
  - event: PostToolUse
    matcher: "Edit|Write"
    command: "~/my-post-hook.sh"
```

**Note**: Skill hooks はグローバルにロードされます（全セッションに影響）。

### Hook Types

| Event | Timing | Use Case |
|-------|--------|----------|
| SessionStart | セッション開始時 | コンテキスト収集 |
| PreToolUse | ツール実行前 | ツールブロック、権限チェック |
| PostToolUse | ツール実行後 | 検証、フィードバック |
| Stop | 停止前 | ループ制御、状態保存 |
| Notification | 通知発生時 | 外部通知連携 |

### Return Format

**PreToolUse**:
```json
{
  "decision": "allow",  // "allow" or exit 2 for deny
  "additionalContext": "Optional message to Claude"
}
```

**PostToolUse**:
```json
{
  "additionalContext": "Validation errors or feedback"
}
```

**Stop**:
```json
{
  "decision": "block",  // "block" to continue, exit 0 to stop
  "additionalContext": "Progress info"
}
```

## Creating Custom Agents

エージェントは `~/.claude/agents/<agent-name>/<agent-name>.md` に配置します。

### Agent Definition

```yaml
---
name: my-agent
description: "Agent description"
model: sonnet  # sonnet, opus, haiku
isolation: worktree  # optional: worktree isolation
allowed-tools:  # optional: restrict tools
  - Read
  - Bash
---

# Agent instructions

Instructions for this agent...
```

### Activation

```bash
# Stow でシンボリックリンク作成
cd ~/dotfiles
stow -d common -t ~ claude
```

### Usage (from Skills or other Agents)

```
Use the Task tool to launch the my-agent agent for this subtask.
```

## Best Practices

### Skills

- 1つのスキルは1つの責務に絞る
- 引数をパースして柔軟に動作させる
- エラーハンドリングを含める
- ヘルプメッセージを提供

### Hooks

- タイムアウトを考慮（Stop: 15s, PostToolUse: 15s, SessionStart: 10s）
- jq 等の依存ツールがない場合は fail-open (exit 0)
- セッション固有の状態は `CLAUDE_SESSION_ID` ベースで管理
- グローバル hooks と skill hooks の違いを理解する

### Agents

- `isolation: worktree` で並列実行時の競合を回避
- allowed-tools で必要最小限のツールに制限
- 構造化された出力フォーマットを定義

### Rules

- 簡潔に記述（長すぎるとトークン消費）
- プロジェクト固有のルールは CLAUDE.md に記述
- グローバルルールは全セッションに影響することを理解

## Troubleshooting

### スキルが表示されない

```bash
# シンボリックリンク確認
ls -la ~/.claude/skills/

# 再作成
cd ~/dotfiles
stow -R -d common -t ~ claude
```

### フックが動作しない

```bash
# settings.json 確認
cat ~/.claude/settings.json | jq .

# フックスクリプトの実行権限確認
ls -la ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
```

### セッションが見つからない

```bash
# セッションデータ確認
ls -la ~/.claude/projects/

# cs でブラウズ
cs
```

## Related Documentation

- [Claude Skills](claude-skills.md) - スキルリファレンス
- [Claude Beacon](claude-beacon.md) - 通知システム
- [Ralph Pattern](ralph.md) - 自律開発ループ
- [Claude Neovim](claude-neovim.md) - Neovim 連携
- [Claude Fallback](claude-fallback.md) - API フォールバック
