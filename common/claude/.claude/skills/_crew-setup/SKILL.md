---
name: _crew-setup
description: 対話的に新規プロジェクトの ralph-crew scheduler (macOS=launchd / Linux=cron) を構築する。worker 構成・タスク・スケジュールをヒアリングし crew.json と scheduler 設定を生成、bootstrap / install までを案内。
user-invocable: true
arguments: "[<path>]"
argument-hint: "[<path>]"
when_to_use: "Use when the user wants to set up ralph-crew autonomous dispatch on a new project (creating .claude/crew.json plus the scheduler entry — launchd plist on macOS, crontab entry on Linux). Triggers: 'set up ralph-crew', 'configure crew on this project', '別 project で crew を試したい', 'Linux の container で crew を動かしたい'."
---

# Crew Setup - 対話式 ralph-crew セットアップ

新規プロジェクトに `ralph-crew` を導入する一連の手順を対話形式で進める。
`.claude/crew.json` の組み立て、scheduler 設定 (macOS は launchd plist、Linux は crontab エントリ) の生成、bootstrap / install までを 1 回の対話で完了させ、終了時に観察コマンドと撤去手順を提示する。

ralph-crew 本体 (`scripts/ralph-crew`) は OS 非依存で、定期的に `dispatch --config <json>` を叩けば動く。このスキルは「何が定期発火するか」を OS に応じて切り替えるだけ。

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

### 1. プロジェクトパスの解決と OS 検出

引数があれば絶対パスに正規化、無ければ `pwd -P` をデフォルトに。
存在しないディレクトリなら即終了し作成を促す。同時に OS を検出し、後の分岐で使う。

```bash
PROJECT="$(cd "${1:-$PWD}" 2>/dev/null && pwd -P)" \
  || { echo "directory not found"; exit 1; }
PROJECT_NAME="$(basename "$PROJECT")"

case "$(uname -s)" in
  Darwin) OS=mac ;;
  Linux)  OS=linux ;;
  *)      echo "unsupported OS: $(uname -s)"; exit 1 ;;
esac
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
| **[OS=mac]** `launchctl` 在中 | 致命 | `command -v launchctl` |
| **[OS=mac]** 既存 `~/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist` | 警告 | 上書き確認材料 |
| **[OS=linux]** `crontab` 在中 | 致命 | `command -v crontab` |
| **[OS=linux]** cron daemon 稼働 | 警告 (無くても crontab 編集可、別途起動必要) | `pgrep -x cron \|\| pgrep -x crond` |
| **[OS=linux]** 既存 crontab の `# ralph-crew:${PROJECT_NAME}` タグ行 | 警告 | 上書き確認材料 (`crontab -l 2>/dev/null \| grep -Fx "# ralph-crew:${PROJECT_NAME}"`) |
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

#### Q6: scheduler 発火間隔

| header | question | options |
|--------|----------|---------|
| Scheduler | scheduler の発火間隔 (macOS=launchd StartInterval, Linux=cron 実行間隔) | 1. 最短タスクと同じ **(Recommended)** / 2. 最短タスクの半分 / 3. カスタム |

- macOS: 秒単位の `StartInterval` として plist に埋め込む
- Linux: 分単位の cron 式に変換 (例: 900 秒 → `*/15 * * * *`)。60 秒未満は cron では表現不可のため最短 1 分に丸める

### 4. crew.json 組み立て

ヒアリング結果から jq でビルドし、`<project>/.claude/crew.json.preview` に書き出す。

worker permissions は role に応じたデフォルトを採用:
- `refactor`: `Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(grep:*), Bash(sed:*), Bash(awk:*), Bash(diff:*), Bash(cat:*), Bash(ls:*), Bash(head:*), Bash(tail:*), Bash(wc:*), Bash(mkdir:*), Bash(mv:*), Bash(cp:*), Bash(rm:*), Bash(cd:*), Read, Edit, Write, Glob, Grep` / deny: `Bash(git push --force:*), Bash(git push -f:*), Bash(rm -rf /:*), Bash(sudo:*)`
- `qa`: lint/test 系 (`Bash(npm:*), Bash(npx:*), Bash(pytest:*), Bash(cargo:*), Bash(go:*), Bash(shellcheck:*), Read, Glob, Grep`) + read-only 系
- `docs`: ファイル比較系 (`Bash(rg:*), Bash(diff:*), Bash(cat:*), Read, Edit, Glob, Grep`) + git 系

system_prompt は role ごとに固定文 (autonomous worker 旨明示)。

### 5. scheduler 設定 組み立て

OS に応じてテンプレートを選び、placeholder を展開する。

#### 5a. macOS (launchd plist)

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

#### 5b. Linux (cron エントリ)

`~/dotfiles/templates/com.user.ralph-crew.cron.template` をベースに展開:

| placeholder | 置換値 |
|-------------|--------|
| `__HOME__` | `$HOME` |
| `__PROJECT__` | `$PROJECT` 絶対パス |
| `__PROJECT_NAME__` | `$PROJECT_NAME` (タグ行に使用) |
| `__CRON_SCHEDULE__` | Q6 の秒数を分に変換した cron 式 (例: 900 → `*/15 * * * *`) |

秒→cron 式変換ヘルパ:

```bash
seconds_to_cron() {
  local sec="$1"
  local min=$(( sec / 60 ))
  if (( min < 1 )); then min=1; fi
  if (( min >= 60 )); then
    local hr=$(( min / 60 ))
    if (( hr >= 24 )); then echo "0 0 * * *"; return; fi
    echo "0 */${hr} * * *"
  else
    echo "*/${min} * * * *"
  fi
}
```

→ `/tmp/ralph-crew/${PROJECT_NAME}/cron.entry.preview` に保存。
先頭のタグ行 `# ralph-crew:${PROJECT_NAME}` が重複除去の目印として使われる。ログディレクトリを先に作成: `mkdir -p /tmp/ralph-crew/${PROJECT_NAME}/logs`。

### 6. プレビュー + 確定確認

生成された 2 ファイル (crew.json + OS 別の scheduler preview) を diff (既存と新規の場合は新規を全文表示) で見せ、最後に AskUserQuestion:

| header | question | options |
|--------|----------|---------|
| Apply | 上記内容で書き込みますか? | 1. 書き込む & launchctl bootstrap して即発火検証する **(Recommended)** / 2. 書き込むだけ (bootstrap は手動でやる) / 3. キャンセル |

### 7. 適用

OS 別に分岐。crew.json の反映は共通。

#### 7a. 共通 (crew.json 反映)

```bash
mv "$PROJECT/.claude/crew.json.preview" "$PROJECT/.claude/crew.json"
```

#### 7b. macOS

**Option 1 (書き込み + 検証)**:
```bash
mv "$HOME/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist.preview" \
   "$HOME/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist"
launchctl bootstrap "gui/$(id -u)" \
   "$HOME/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist"
launchctl kickstart -p "gui/$(id -u)/com.user.ralph-crew-${PROJECT_NAME}"
sleep 5
```
- `launchctl print` で `last exit code` を確認
- `tail -n 50` で `/tmp/ralph-crew/${PROJECT_NAME}/logs/launchd.err` と dispatch log を表示
- `ralph-crew status --config "$PROJECT/.claude/crew.json"` で worker 状態確認

**Option 2 (書き込みのみ)**: `mv` のみ実行し、bootstrap コマンドを次のステップとして表示。

#### 7c. Linux (cron)

idempotent install: 既存エントリを除去してから新エントリを追記する。

**Option 1 (書き込み + 検証)**:
```bash
mkdir -p "/tmp/ralph-crew/${PROJECT_NAME}/logs"

# 現行 crontab を取得し、同プロジェクトのタグから次のタグ行 or ファイル末尾までを削除
TAG="# ralph-crew:${PROJECT_NAME}"
NEW_CRON="$(mktemp)"
{
  crontab -l 2>/dev/null | awk -v tag="$TAG" '
    $0 == tag { skip = 1; next }           # タグ行を除外し、続く 1 行 (command 行) も除外
    skip > 0  { skip--; next }
    { print }
  '
  cat "/tmp/ralph-crew/${PROJECT_NAME}/cron.entry.preview"
} > "$NEW_CRON"

crontab "$NEW_CRON"
rm -f "$NEW_CRON" "/tmp/ralph-crew/${PROJECT_NAME}/cron.entry.preview"

# 即時発火検証
"$HOME/dotfiles/scripts/ralph-crew" dispatch --config "$PROJECT/.claude/crew.json" || true
```
- `crontab -l | grep -A1 -Fx "$TAG"` で登録確認
- `tail -n 50 /tmp/ralph-crew/${PROJECT_NAME}/logs/cron.err` と dispatch log を表示
- `ralph-crew status --config "$PROJECT/.claude/crew.json"` で worker 状態確認

**Option 2 (書き込みのみ)**: `crontab` 反映のみ行い、即時発火検証をスキップ。

#### 7d. Option 3 (キャンセル、OS 共通)

`.preview` ファイルを残したまま中断 (再開時に diff レビュー可能)。

### 8. 完了報告

成功時に以下を表示:

- 設置パス (`crew.json` と OS 別 scheduler ファイル)
  - macOS: `~/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist`
  - Linux: crontab 内 `# ralph-crew:${PROJECT_NAME}` タグ行 + 次行
- 観察コマンド (共通)
  - `tmux attach -t crew-${PROJECT_NAME}`
  - `tail -f /tmp/ralph-crew/${PROJECT_NAME}/logs/dispatch.log`
  - `ralph-crew status --config "$PROJECT/.claude/crew.json"`
- 観察コマンド (OS 別)
  - macOS: `launchctl print gui/$(id -u)/com.user.ralph-crew-${PROJECT_NAME}`
  - Linux: `crontab -l | grep -A1 -Fx "# ralph-crew:${PROJECT_NAME}"`, `tail -f /tmp/ralph-crew/${PROJECT_NAME}/logs/cron.err`
- 撤去コマンド
  - 共通: `ralph-crew teardown --config "$PROJECT/.claude/crew.json"`
  - macOS:
    ```bash
    launchctl bootout "gui/$(id -u)/com.user.ralph-crew-${PROJECT_NAME}"
    rm "$HOME/Library/LaunchAgents/com.user.ralph-crew-${PROJECT_NAME}.plist"
    ```
  - Linux (タグ行とその次の 1 行を削除):
    ```bash
    TAG="# ralph-crew:${PROJECT_NAME}"
    crontab -l 2>/dev/null | awk -v tag="$TAG" '
      $0 == tag { skip = 1; next }
      skip > 0  { skip--; next }
      { print }
    ' | crontab -
    ```

## エッジケース

- **[mac]** 既存 plist が同 Label でロード済み → `launchctl bootout` 案内 → 再 bootstrap
- **[linux]** 既存 crontab に同タグ行あり → idempotent install で差し替え (警告のみ出して続行)
- **[linux]** cron daemon (cron / crond) が稼働していない → crontab 登録は可能だが発火しない。`service cron start` / container entrypoint への追加を案内
- `gh auth status` 失敗 → `gh auth login` 案内して中断
- origin 無し / push 認証 NG → fix モード選択時のみ致命、issue-only / none なら警告のみで続行
- カレントディレクトリが git repo でない → 致命 (ralph-crew は worktree を要求するため)
- `.claude/crew.json` が既存 → 上書き確認 (diff 提示)

## 注意事項

- **ralph-crew 本体は OS 非依存**: scheduler 層だけが OS 依存。新しい scheduler (systemd-user timer など) を追加する場合も本スキルの OS 分岐に分岐節を追加するだけでよい
- **launchctl bootstrap は重複 Label でエラー**: project ごとに Label を namespaced する設計のため複数プロジェクト併存可
- **crontab はプロセス単位の共有リソース**: タグ行 `# ralph-crew:${PROJECT_NAME}` + 次行を 1 エントリとして扱う。複数プロジェクト併存可
- **plist / cron の log path も namespaced**: 元 template は `/tmp/ralph-crew/logs/...` 固定だが、複数プロジェクト同時運用時の上書き合戦を避けるため `${PROJECT_NAME}` を挟む
- **AskUserQuestion をブロックする hook を追加してはならない**: このスキルは対話前提
- **生成した crew.json は .gitignore 対象が多い**: dotfiles では `.claude/crew.json` を gitignore している。プロジェクト側の方針に合わせるよう案内 (commit するなら secrets を含めない)
- **fix モードを選んだ場合は実 PR が作成される**: パブリックリポジトリでは特に最初は issue-only から始めることを Q4 の Recommended に反映
