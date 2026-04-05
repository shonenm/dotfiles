# Ralph Schedule - 予約投稿型 Claude TUI 実行

指定時刻に Claude TUI を自動起動し、`/ralph-local` で自律実行させるワンショットスケジューラー。セッション切れ時でもシェルスクリプトのみで予約の登録・実行が完結する。

`ralph-crew` (常駐型定期ディスパッチ) とは異なり、一回限りのスケジュール実行に特化。

## Architecture

```
ralph-schedule "タスク" --at +2h --branch fix/bug
  |
  +-- 時刻パース (相対/絶対)
  +-- worktree 作成 (--branch 指定時)
  +-- プロンプトファイル作成
  +-- ジョブメタデータ作成
  +-- launchd (macOS) / at (Linux) 登録
  v

[指定時刻]
  |
  v
ralph-schedule-exec.sh <job-id>
  |
  +-- ジョブメタデータ読み込み、status -> running
  +-- Self-cleanup: launchd bootout + plist 削除
  +-- tmux セッション確認/作成
  +-- worktree 確認/作成 + tmux ウィンドウ作成
  +-- ralph_setup_worker_settings (パーミッション設定)
  +-- claude --model <model> 起動
  +-- _wait_for_tui (ポーリングで TUI 準備待ち)
  +-- /ralph-local 'Read <prompt_file>...' --skip-plan 注入
  +-- status -> done
  v
Claude TUI が /ralph-local ループで自律実行
```

## Usage

### 予約登録

```bash
# 相対時刻
ralph-schedule "認証バグを修正して" --at +30m --branch fix/auth-bug
ralph-schedule "テスト追加" --at +2h --branch feat/tests --base main
ralph-schedule "lint修正" --at +1h30m

# 絶対時刻 (HH:MM - 過去なら翌日に繰り越し)
ralph-schedule "リファクタリング" --at 09:00 --branch refactor/cleanup

# 絶対日時
ralph-schedule "機能追加" --at "2026-03-28 14:00" --branch feat/new --model opus
```

### 管理

```bash
ralph-schedule list              # テーブル形式で一覧
ralph-schedule list --json       # JSON 形式
ralph-schedule cancel <job-id>   # 個別キャンセル
ralph-schedule cancel --all      # 全 pending ジョブキャンセル
```

### クリーンアップ

```bash
claude-gc              # dry-run: 完了済みジョブ + 孤立 plist を表示
claude-gc --force      # 実際に削除
```

## CLI Options

| Option | Default | Description |
|--------|---------|-------------|
| `<prompt>` | (必須) | Claude に送るタスク記述 |
| `--at <time-spec>` | (必須) | 実行時刻 |
| `--branch <name>` | (なし) | worktree + tmux ウィンドウを作成 |
| `--base <ref>` | HEAD | `--branch` 使用時のベース ref |
| `--model <model>` | sonnet | Claude モデル |

## Time Formats

| Format | Example | Description |
|--------|---------|-------------|
| `+Nm` | `+30m` | N 分後 |
| `+Nh` | `+2h` | N 時間後 |
| `+NhMm` | `+1h30m` | N 時間 M 分後 |
| `HH:MM` | `09:00` | 当日の指定時刻 (過去なら翌日) |
| `YYYY-MM-DD HH:MM` | `2026-03-28 14:00` | 絶対日時 (過去はエラー) |

## State Directory

```
/tmp/ralph-schedule/
  jobs/<job-id>.json       # ジョブメタデータ
  prompts/<job-id>.md      # プロンプトファイル
  logs/<job-id>.log        # executor 実行ログ
  logs/<job-id>.out        # launchd stdout
  logs/<job-id>.err        # launchd stderr
```

ジョブ ID: `sched-<epoch>-<random5>` (時系列ソート可能 + 一意性)

Status 遷移: `pending` -> `running` -> `done` / `failed` (cancel 時は `cancelled`)

## Scheduling

### macOS: launchd (StartCalendarInterval)

`templates/com.user.ralph-schedule.plist` をベースに、プレースホルダーを sed で置換して plist を生成。`StartCalendarInterval` で指定時刻に発火、executor 内で self-cleanup (bootout + plist 削除)。

### Linux: at

`at` コマンドが利用可能ならそれを使用。なければエラー終了。

## Tmux Session Strategy

executor は launchd から呼ばれるため `$TMUX` が未設定。worktree 作成と tmux ウィンドウ作成を分離して直接実行する:

- 登録時の tmux セッション名を記録 (`$TMUX` 未設定時は `ralph-schedule` をデフォルトに)
- executor はセッション存在確認 -> なければ作成
- `tmux new-window -t <session> -n <window> -c <dir>` で直接ウィンドウ作成

## File Structure

```
dotfiles/
+-- scripts/
|   +-- ralph-schedule              # メイン CLI (add/list/cancel)
|   +-- ralph-schedule-exec.sh      # launchd/at から呼ばれる executor
|   +-- ralph-lib.sh                # 共有ユーティリティ (permissions setup)
|   +-- wt-lib.sh                   # worktree + tmux ウィンドウ管理ライブラリ
|   +-- claude-gc                   # クリーンアップ (_gc_ralph_schedule 追加)
+-- templates/
|   +-- com.user.ralph-schedule.plist  # launchd plist テンプレート
+-- docs/
    +-- ralph-schedule.md              # このドキュメント
```

## Design Decisions

- ワンショット: ralph-crew (常駐定期ディスパッチ) とは異なり、一回限りのスケジュール実行に特化
- Claudeレス登録: シェルスクリプトのみで予約完結。セッション切れ時でも使用可能
- worktree 即時作成: 登録時に worktree を作成し、executor は存在確認のみ (フォールバックで作成も可)
- launchd self-cleanup: executor が自身の plist を bootout + 削除。再発火を防止
- ファイル経由プロンプト注入: tmux send-keys のエスケープ問題を回避 (ralph-crew と同じパターン)
- claude-gc 統合: 完了済みジョブと孤立 plist のクリーンアップを既存 GC フローに統合
