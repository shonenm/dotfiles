---
name: _crew-setup
description: 対話的に新規プロジェクトの ralph-crew + launchd を構築する。worker 構成・タスク・スケジュールをヒアリングし crew.json と plist を生成、bootstrap までを案内。
user-invocable: true
arguments: "[<path>]"
argument-hint: "[<path>]"
when_to_use: "Use when the user wants to set up ralph-crew autonomous dispatch on a new project (creating .claude/crew.json and the macOS launchd plist), especially when they say things like 'set up cron for ralph-crew', 'configure crew on this project', or '別 project で crew を試したい'."
---

# Crew Setup - 対話式 ralph-crew + launchd セットアップ

新規プロジェクトに `ralph-crew` を導入する一連の手順を対話形式で進める。
`.claude/crew.json` の組み立て、launchd plist の生成、bootstrap までを 1 回の対話で完了させ、終了時に観察コマンドと撤去手順を提示する。

## 引数

| 引数 | 説明 |
|------|------|
| (なし) | カレントディレクトリを対象にする |
| `<project-path>` | 対象プロジェクトの絶対パス |

### 使用例

```
/_crew-setup
/_crew-setup ~/works/syntopic-bot
```

## 手順

### 1. プロジェクトパスの解決

引数があれば絶対パスに正規化、無ければ `pwd -P` をデフォルトに。
存在しないディレクトリなら即終了し作成を促す。

```bash
PROJECT="$(cd "${1:-$PWD}" 2>/dev/null && pwd -P)" \
  || { echo "directory not found"; exit 1; }
PROJECT_NAME="$(basename "$PROJECT")"
```

### 2. 前提チェック (並列実行)

すべて並列に走らせて、致命/警告/情報を仕分けて 1 まとめで報告:

| チェック | 致命度 | コマンド |
|----------|--------|----------|
| `claude` 在中 | 致命 | `command -v claude` |
| `tmux` 在中 | 致命 | `command -v tmux` |
| `jq` 在中 | 致命 | `command -v jq` |
| `gh` 在中 | fix モード時致命 | `command -v gh` |
| `gh auth status` | fix モード時致命 | `gh auth status` |
| `$PROJECT/.git` 存在 | 致命 | `[[ -d "$PROJECT/.git" ]]` |
| origin remote | fix モード時致命 | `git -C "$PROJECT" remote get-url origin` |
| origin push 認証 | fix モード時致命 | `git -C "$PROJECT" ls-remote --heads origin` |
| 既存 `.claude/crew.json` | 警告 | 上書き確認材料 |
| 既存 `~/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist` | 警告 | 上書き確認材料 |
| `~/.claude.json` | 警告無し (無くても OK、ralph-lib の `ralph_preaccept_trust` が no-op) | `[[ -f ~/.claude.json ]]` |

致命があれば `### 致命的な前提不足` セクションで列挙し中断。
警告は `### 既存ファイルあり` セクションでまとめ、後の上書き確認に使う。

### 3. 構成ヒアリング (AskUserQuestion)

次の順で質問。各質問は一度に複数並列で投げて良い (回答を待ち合わせて統合):

#### Q1: ワーカー構成

| header | question | options |
|--------|----------|---------|
| Worker | このプロジェクトでどんな role の worker を置く? | 1. `refactor` (汎用リファクタ・バグ潰し, sonnet) **(Recommended)** / 2. `qa` (lint/test 監視, haiku) / 3. `docs` (docs drift 監視, haiku) / 4. カスタム |

カスタムの場合は AskUserQuestion で `id` を free-text 取得 (multiSelect: false, options に "Other" が自動付与される)。

複数 worker を置きたい場合は別ターンで再度 AskUserQuestion を出す ("追加で worker を置きますか?")。

#### Q2: ワーカー単位の model

| header | question | options |
|--------|----------|---------|
| Model | `<worker-id>` の model は? | 1. `haiku` (高速・安価) / 2. `sonnet` (Recommended) / 3. `opus` |

#### Q3: タスク種類

worker ごとに task を 1 本以上作る:

| header | question | options |
|--------|----------|---------|
| Task | `<worker-id>` に何をやらせる? | 1. lint/typecheck の監視 / 2. テスト失敗を issue 化 / 3. docs drift 自動修正 / 4. カスタム prompt |

カスタムなら multi-line prompt を free-text 取得 (AskUserQuestion で長文を取れない場合は、要件を 1 行で取得して prompt body は AI が補完して提示し、最後に diff レビューで確認する)。

#### Q4: action モード

| header | question | options |
|--------|----------|---------|
| Action | task `<task-id>` のアクションモード | 1. `fix` (worktree → commit → push → PR) **(Recommended for refactor)** / 2. `issue-only` (検出して issue を立てるだけ) / 3. `none` (raw prompt、出力に従う) |

#### Q5: スケジュール

| header | question | options |
|--------|----------|---------|
| Schedule | task `<task-id>` の発火間隔 | 1. 5 分 / 2. 15 分 **(Recommended)** / 3. 30 分 / 4. 1 時間 |

#### Q6: launchd 発火間隔

| header | question | options |
|--------|----------|---------|
| Launchd | launchd plist の StartInterval | 1. 最短タスクと同じ **(Recommended)** / 2. 最短タスクの半分 / 3. カスタム秒数 |

### 4. crew.json 組み立て

ヒアリング結果から jq でビルドし、`<project>/.claude/crew.json.preview` に書き出す。

worker permissions は role に応じたデフォルトを採用:
- `refactor`: `Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(grep:*), Bash(sed:*), Bash(awk:*), Bash(diff:*), Bash(cat:*), Bash(ls:*), Bash(head:*), Bash(tail:*), Bash(wc:*), Bash(mkdir:*), Bash(mv:*), Bash(cp:*), Bash(rm:*), Bash(cd:*), Read, Edit, Write, Glob, Grep` / deny: `Bash(git push --force:*), Bash(git push -f:*), Bash(rm -rf /:*), Bash(sudo:*)`
- `qa`: lint/test 系 (`Bash(npm:*), Bash(npx:*), Bash(pytest:*), Bash(cargo:*), Bash(go:*), Bash(shellcheck:*), Read, Glob, Grep`) + read-only 系
- `docs`: ファイル比較系 (`Bash(rg:*), Bash(diff:*), Bash(cat:*), Read, Edit, Glob, Grep`) + git 系

system_prompt は role ごとに固定文 (autonomous worker 旨明示)。

### 5. launchd plist 組み立て

`~/dotfiles/templates/com.user.ralph-crew.plist` をベースに、以下を **すべて** project-namespaced:

| placeholder | 置換値 |
|-------------|--------|
| `__HOME__` | `$HOME` |
| `__PROJECT__` | `$PROJECT` 絶対パス |
| `__INTERVAL__` | Q6 の秒数 |
| `com.user.ralph-crew` Label | `com.user.ralph-crew-${PROJECT_NAME}` |
| `/tmp/ralph-crew/logs/launchd.out` | `/tmp/ralph-crew/${PROJECT_NAME}/logs/launchd.out` |
| `/tmp/ralph-crew/logs/launchd.err` | `/tmp/ralph-crew/${PROJECT_NAME}/logs/launchd.err` |

→ `~/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist.preview` に保存。
`plutil -lint` で構文検証。

### 6. プレビュー + 確定確認

生成された 2 ファイルを diff (既存と新規の場合は新規を全文表示) で見せ、最後に AskUserQuestion:

| header | question | options |
|--------|----------|---------|
| Apply | 上記内容で書き込みますか? | 1. 書き込む & launchctl bootstrap して即発火検証する **(Recommended)** / 2. 書き込むだけ (bootstrap は手動でやる) / 3. キャンセル |

### 7. 適用

選択肢に応じて:

**Option 1 (書き込み + 検証)**:
```bash
mv "$PROJECT/.claude/crew.json.preview" "$PROJECT/.claude/crew.json"
mv "$HOME/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist.preview" \
   "$HOME/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist"
launchctl bootstrap "gui/$(id -u)" \
   "$HOME/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist"
launchctl kickstart -p "gui/$(id -u)/com.user.ralph-crew-${PROJECT_NAME}"
sleep 5
```
- `launchctl print` で `last exit code` を確認
- `tail -n 50` で launchd stderr (`/tmp/ralph-crew/${PROJECT_NAME}/logs/launchd.err`) と dispatch log を表示
- `ralph-crew status --config "$PROJECT/.claude/crew.json"` で worker 状態確認

**Option 2 (書き込みのみ)**:
- `mv` 2 つだけ実行
- bootstrap コマンドを次のステップとして表示

**Option 3 (キャンセル)**:
- `.preview` ファイルを残したまま中断 (再開時に diff レビュー可能)

### 8. 完了報告

成功時に以下を表示:

- 設置パス (crew.json / plist)
- launchd Label
- 観察コマンド
  - `tmux attach -t crew-${PROJECT_NAME}`
  - `tail -f /tmp/ralph-crew/${PROJECT_NAME}/logs/dispatch.log`
  - `ralph-crew status --config "$PROJECT/.claude/crew.json"`
- 撤去コマンド
  - `launchctl bootout "gui/$(id -u)/com.user.ralph-crew-${PROJECT_NAME}"`
  - `ralph-crew teardown --config "$PROJECT/.claude/crew.json"`
  - `rm "$HOME/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist"`

## エッジケース

- 既存 plist が同 Label でロード済み → `launchctl bootout` 案内 → 再 bootstrap
- `gh auth status` 失敗 → `gh auth login` 案内して中断
- origin 無し / push 認証 NG → fix モード選択時のみ致命、issue-only / none なら警告のみで続行
- カレントディレクトリが git repo でない → 致命 (ralph-crew は worktree を要求するため)
- `.claude/crew.json` が既存 → 上書き確認 (diff 提示)

## 注意事項

- **launchctl bootstrap は重複 Label でエラー**: project ごとに Label を namespaced する設計のため複数プロジェクト併存可
- **plist の log path も namespaced**: 元 template は `/tmp/ralph-crew/logs/launchd.{out,err}` 固定だが、複数プロジェクト同時運用時の上書き合戦を避けるため `${PROJECT_NAME}` を挟む
- **AskUserQuestion をブロックする hook を追加してはならない**: このスキルは対話前提
- **生成した crew.json は .gitignore 対象が多い**: dotfiles では `.claude/crew.json` を gitignore している。プロジェクト側の方針に合わせるよう案内 (commit するなら secrets を含めない)
- **fix モードを選んだ場合は実 PR が作成される**: パブリックリポジトリでは特に最初は issue-only から始めることを Q4 の Recommended に反映
