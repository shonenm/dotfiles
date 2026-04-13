# Ralph Crew - 定期ディスパッチ自律ワーカー管理

常駐 Claude TUI ワーカーを tmux 上で管理し、設定ファイルのスケジュールに基づいてタスクを定期注入するシステム。`ralph-parallel` とは独立したライフサイクルモデル (一時的な並列実行 vs 常駐ワーカーへの定期注入)。

## Architecture

```
launchd (定期発火, e.g. 15分間隔)
  |
  v
ralph-crew dispatch (flock で排他制御)
  |
  +-- crew.json を読み取り
  +-- 各タスクの schedule 評価 (interval 経過判定, epoch 比較)
  +-- 対象ワーカーの状態確認 (状態ファイルベース)
  |     idle  -> タスク注入 (常にファイル経由 + tmux send-keys)
  |     running -> スキップ
  |     dead  -> 自動再起動 (sliding window で制限)
  +-- action モードに応じたプロンプト生成
  |     fix        -> worktree 作成 → 修正 → commit → push → PR
  |     issue-only -> 問題報告のみ (GitHub issue)
  +-- 実行時刻を記録
  v
tmux session: "ralph-crew"
  +-- window "crew/<worker-id>" : claude TUI (persistent, Notification hook で状態通知)
```

リーダー (Claude インスタンス) は置かない:
- タスクルーティングは設定ファイルで静的に定義
- シェルスクリプトのディスパッチャーなら launchd 統合が簡潔でデバッグも容易
- KB アクセスはワーカー自身が MCP 経由で実行

## Usage

### セットアップ

```bash
# 1. プロジェクト配下に設定ファイルを作成
cd /path/to/project
mkdir -p .claude
cp ~/dotfiles/templates/crew.example.json .claude/crew.json
# crew.json を編集: workers, tasks, schedule を設定

# 2. ワーカーを起動 (プロジェクトディレクトリで実行)
ralph-crew init

# 3. 手動ディスパッチ
ralph-crew dispatch

# 4. 状態確認
ralph-crew status
```

設定ファイルはプロジェクトの `.claude/crew.json` に配置する。プロジェクトディレクトリは config ファイルのパスから自動導出される。`tmux_session` と `state_dir` を省略するとプロジェクト名ベースのデフォルト値が使われる。

### launchd で定期実行

```bash
# __INTERVAL__ は秒数 (例: 900 = 15分, 1800 = 30分, 3600 = 1時間)
# __PROJECT__ はプロジェクトの絶対パス
cp ~/dotfiles/templates/com.user.ralph-crew.plist ~/Library/LaunchAgents/
sed -i '' "s|__HOME__|$HOME|g; s|__PROJECT__|/path/to/project|g; s|__INTERVAL__|900|g" ~/Library/LaunchAgents/com.user.ralph-crew.plist

launchctl load ~/Library/LaunchAgents/com.user.ralph-crew.plist
```

`__INTERVAL__` を crew.json の最短 `schedule.minutes` に合わせて設定すること。dispatch 側でタスクごとの間隔を個別に評価するため、launchd の発火間隔は最短タスク以下であれば良い。

### スキル経由

```
/ralph-crew init
/ralph-crew dispatch
/ralph-crew status
/ralph-crew send qa "Run npm test and report results"
/ralph-crew restart qa
/ralph-crew cleanup
/ralph-crew teardown
```

## Action Modes

タスクの `action` フィールドで検出後の行動を制御する。

| Action | デフォルト | 動作 |
|--------|-----------|------|
| `fix` | Yes | 問題検出 → worktree で修正 → commit → push → PR 作成。修正不能なら issue にフォールバック |
| `issue-only` | No | 問題検出 → GitHub issue 作成のみ。修正は試みない |
| `none` | No | プロンプトをそのまま注入 (wrapper 無し)。ドライラン・レポートのみ等、タスクプロンプト自体が終端挙動を定義しているケース向け |

### fix モードのワークフロー

```
1. project_dir でチェック実行 (read-only)
2. 問題検出
3. git worktree add /tmp/ralph-crew/fix/<task-id>-<ts> -b crew/<task-id>-<ts> HEAD
4. worktree 内で修正 → commit → push
5. gh pr create
6. worktree 削除、project_dir に戻る
```

fix モードのワーカーは自動的に git push / worktree 権限が付与される (force push は deny)。

## Task Patterns

`pattern` フィールドは意味論的な分類。dispatch ロジックは共通 (schedule 評価 -> idle 確認 -> プロンプト注入)。

| Pattern | 用途 | 例 |
|---------|------|-----|
| `standing` | 定期実行される固定プロンプト | テスト監視、lint チェック、品質レポート |
| `kb_pull` | MCP 経由で KB にアクセスしてタスク取得・実行 | Notion/Linear からタスク取得 |

## Worker State Detection

Notification hook ベースの状態検出:

1. ワーカーの `.claude/settings.local.json` に Notification hook を自動設定
2. `idle_prompt` イベントで `${STATE_DIR}/workers/${worker_id}.status` を `idle` に更新
3. タスク注入時に `running` に更新

状態: `idle` / `running` / `dead` / `unknown`

## Auto-restart

ワーカーの pane が消失した場合、dispatch 時に自動再起動を試みる。再起動制限:

- sliding window: 直近5分以内に3回再起動 -> 無効化
- `restart_timestamps` 配列でタイムスタンプを追跡

## Runtime Directory

```
/tmp/ralph-crew/<project-name>/
  workers/           # {worker_id}.json (pane_id, started, restart_timestamps)
                     # {worker_id}.status (idle / running / unknown)
  dispatch/          # {task_id}.last (最終実行 epoch)
  fix/               # fix モードの一時 worktree ({task_id}-{timestamp})
  prompts/           # タスクプロンプト一時ファイル (24h TTL で自動削除)
  system-prompts/    # ワーカー system_prompt ファイル
  logs/              # dispatch.log, launchd.out, launchd.err
  dispatch.lock      # flock 用ロックファイル
```

## Config Schema

配置場所: `<project>/.claude/crew.json`

```jsonc
{
  // "tmux_session": "crew-<project-name>",  // optional (default: derived from project dir)
  // "state_dir": "/tmp/ralph-crew/<project-name>",  // optional (default: derived from project dir)
  "workers": [
    {
      "id": "qa",
      "model": "sonnet",         // claude model
      "mcp_config": null,        // MCP config file path (for kb_pull pattern)
      "system_prompt": "...",    // append-system-prompt
      "permissions": {           // .claude/settings.local.json permissions
        "allow": ["Bash(npm:*)"],
        "deny": ["Bash(git push:*)"]
      }
    }
  ],
  "tasks": [
    {
      "id": "test-watch",
      "pattern": "standing",     // standing | kb_pull
      "worker_id": "qa-frontend",
      "action": "fix",           // "fix" (default) | "issue-only"
      "prompt": "Run `npm test`...",
      "schedule": {
        "type": "interval",
        "minutes": 30
      }
    }
  ]
}
```

## File Structure

```
dotfiles/
+-- scripts/
|   +-- ralph-lib.sh            # Shared utilities (permissions setup)
|   +-- ralph-crew           # Crew management script
+-- templates/
|   +-- crew.example.json       # Config template
|   +-- com.user.ralph-crew.plist  # launchd plist template
+-- common/claude/.claude/
|   +-- skills/
|       +-- ralph-crew/SKILL.md # /ralph-crew skill
+-- docs/
    +-- ralph-crew.md           # This documentation
```

## Design Decisions

- リーダーレス: LLM リーダーを置かず、シェルスクリプト + launchd で静的ルーティング
- Notification hook: capture-pane の `❯` 検出より信頼性が高い状態検出
- ファイル経由タスク注入: tmux send-keys のエスケープ問題を完全に回避
- flock 排他制御: launchd の重複発火を防止
- sliding window 再起動制限: 単純なカウンターではなく時間ベースで判定
- `max_budget_usd` 非対応: persistent TUI では累積消費で予算到達時にフリーズするため
- fix モードで worktree 分離: チェックは project_dir (read-only)、修正は一時 worktree で実施。ワーカー間の競合を防止
- ralph-orchestrate と独立: ライフサイクルモデルが異なる (一時的 vs 常駐)

## TODO

- プロンプトテンプレート変数 + フォーカスローテーション: 静的プロンプトだと毎回同じ箇所しかチェックしない問題への対策。crew.json に `focus_rotation` 配列を持たせ、dispatch のたびに次の観点を選んでプロンプトに展開する。`{{focus}}`, `{{recent_changes}}`, `{{last_result}}` などのテンプレート変数をサポート。実装コスト自体は低い (シェルスクリプトで配列インデックスを回すだけ) が、実際に品質向上に寄与するかは運用してから判断する
