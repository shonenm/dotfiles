---
name: d-crew-setup
description: 対話的に新規プロジェクトの ralph-crew を構築する。worker 構成・タスク・スケジュールをヒアリングして crew.json を生成し、tmux session 内で `ralph-crew daemon` を常駐させる。外部 scheduler (launchd/cron) は不要。
user-invocable: true
arguments: "[<path>]"
argument-hint: "[<path>]"
when_to_use: "Use when the user wants to set up ralph-crew autonomous dispatch on a new project (creating .claude/crew.json and launching the ralph-crew daemon inside a tmux session). Triggers: 'set up ralph-crew', 'configure crew on this project', '別 project で crew を試したい'."
---

# Crew Setup - 対話式 ralph-crew セットアップ

新規プロジェクトに `ralph-crew` を導入する一連の手順を対話形式で進める。
`.claude/crew.json` を組み立て、`ralph-crew init` で worker を立て、`ralph-crew daemon` を同じ tmux session の専用 window に常駐させて periodic dispatch を実現する。

外部 scheduler (launchd / cron / systemd) は使わない。daemon は tmux session 内で動き、tmux-continuum (`@continuum-restore on`) がサーバ再起動時にセッションを復元する。動作要件は `bash + tmux + claude` のみで、macOS / Linux / container のいずれでも同じ機構で動く。

## 引数

| 引数 | 説明 |
|------|------|
| (なし) | カレントディレクトリを対象にする |
| `<project-path>` | 対象プロジェクトの絶対パス |

### 使用例

```
/d-crew-setup
/d-crew-setup ~/works/syntopic-bot
```

## 手順

### 1. プロジェクトパスの解決 + 環境コンテキスト

引数があれば絶対パスに正規化、無ければ `pwd -P` をデフォルトに。
存在しないディレクトリなら即終了し作成を促す。

```bash
PROJECT="$(cd "${1:-$PWD}" 2>/dev/null && pwd -P)" \
  || { echo "directory not found"; exit 1; }
PROJECT_NAME="$(basename "$PROJECT")"
eval "$(${DOTFILES_DIR:-$HOME/dotfiles}/scripts/env-context)"
```

`env-context` 出力の `$ENV_TYPE` と `$TMUX_LOCATION` / `$TMUX_ACCESS_CMD` でその後の分岐を決める。

### 1.5. container 内で呼ばれた場合は host にリダイレクト

`$ENV_TYPE == "linux-container"` (= `/.dockerenv` あり) の場合、`ralph-crew init` を **container-local tmux** に着地させてはいけない (opensessions が観察できず、container 再起動で消える)。以下の案内だけ出してスキルは終了する:

```
このプロジェクトは container 内にあります (container=$CONTAINER_NAME).
ralph-crew は $HOST_MACHINE の host tmux で起動する必要があります。

次のコマンドを host で実行してください:
  ssh $HOST_MACHINE '
    cd <project path on host> &&
    ~/dotfiles/scripts/ralph-crew init --config <path>/.claude/crew.json &&
    tmux new-window -d -t crew-$PROJECT_NAME -n scheduler \
      "exec ralph-crew daemon --interval <sec> --config <path>/.claude/crew.json"
  '
```

crew.json 自体は container 内 (bind mount 経由で host からも見える) に置いて構わない。起動だけが host で行われれば OK。

**このステップで止まれば以降の step 2-8 はスキップ**。

### 2. 前提チェック (並列実行)

すべて並列に走らせて、致命/警告/情報を仕分けて 1 まとめで報告:

| チェック | 致命度 | コマンド |
|----------|--------|----------|
| `claude` 在中 | 致命 | `command -v claude` |
| `tmux` 在中 | 致命 | `command -v tmux` |
| `jq` 在中 | 致命 | `command -v jq` |
| `ralph-crew` 在中 | 致命 | `command -v ralph-crew` |
| `gh` 在中 | fix モード時致命 | `command -v gh` |
| `gh auth status` | fix モード時致命 | `gh auth status` |
| `$PROJECT/.git` 存在 | 致命 | `[[ -d "$PROJECT/.git" ]]` |
| origin remote | fix モード時致命 | `git -C "$PROJECT" remote get-url origin` |
| origin push 認証 | fix モード時致命 | `git -C "$PROJECT" ls-remote --heads origin` |
| 既存 `.claude/crew.json` | 警告 | 上書き確認材料 |
| 既存 `ralph-crew` tmux session | 警告 | `tmux has-session -t ralph-crew` |
| 既存 daemon pidfile `/tmp/ralph-crew/${PROJECT_NAME}/daemon.pid` が生きている | 警告 | 既存 daemon の停止を案内 |
| `~/.claude.json` | 警告無し (無くても OK、ralph-lib の `ralph_preaccept_trust` が no-op) | `[[ -f ~/.claude.json ]]` |

致命があれば `### 致命的な前提不足` セクションで列挙し中断。
警告は `### 既存ファイルあり` セクションでまとめ、後の上書き確認に使う。

### 3. 構成ヒアリング (AskUserQuestion)

次の順で質問。各質問は一度に複数並列で投げて良い (回答を待ち合わせて統合):

#### Q1: ワーカー構成

| header | question | options |
|--------|----------|---------|
| Worker | このプロジェクトでどんな role の worker を置く? | 1. `refactor` (汎用リファクタ・バグ潰し, sonnet) **(Recommended)** / 2. `qa` (lint/test 監視, haiku) / 3. `docs` (docs drift 監視, haiku) / 4. カスタム |

カスタムの場合は AskUserQuestion で `id` を free-text 取得。
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

#### Q4: action モード

| header | question | options |
|--------|----------|---------|
| Action | task `<task-id>` のアクションモード | 1. `fix` (worktree → commit → push → PR) **(Recommended for refactor)** / 2. `issue-only` (検出して issue を立てるだけ) / 3. `none` (raw prompt) |

#### Q5: タスク発火間隔 (per-task)

| header | question | options |
|--------|----------|---------|
| Schedule | task `<task-id>` の発火間隔 | 1. 5 分 / 2. 15 分 **(Recommended)** / 3. 30 分 / 4. 1 時間 |

crew.json の `tasks[].schedule.minutes` に分単位で格納される。

#### Q6: daemon tick 間隔

| header | question | options |
|--------|----------|---------|
| Daemon | `ralph-crew daemon --interval` (秒) | 1. 60 秒 **(Recommended)** / 2. 最短タスク間隔の半分 / 3. カスタム秒数 |

Q5 で設定される per-task interval とは別レイヤー: daemon tick はディスパッチ候補を評価する頻度、per-task interval は実際にディスパッチする最低間隔。tick < task interval を維持する。

### 4. crew.json 組み立て

ヒアリング結果から jq でビルドし、`<project>/.claude/crew.json.preview` に書き出す。

worker permissions は role に応じたデフォルトを採用:
- `refactor`: `Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(grep:*), Bash(sed:*), Bash(awk:*), Bash(diff:*), Bash(cat:*), Bash(ls:*), Bash(head:*), Bash(tail:*), Bash(wc:*), Bash(mkdir:*), Bash(mv:*), Bash(cp:*), Bash(rm:*), Bash(cd:*), Read, Edit, Write, Glob, Grep` / deny: `Bash(git push --force:*), Bash(git push -f:*), Bash(rm -rf /:*), Bash(sudo:*)`
- `qa`: lint/test 系 (`Bash(npm:*), Bash(npx:*), Bash(pytest:*), Bash(cargo:*), Bash(go:*), Bash(shellcheck:*), Read, Glob, Grep`) + read-only 系
- `docs`: ファイル比較系 (`Bash(rg:*), Bash(diff:*), Bash(cat:*), Read, Edit, Glob, Grep`) + git 系

system_prompt は role ごとに固定文 (autonomous worker 旨明示)。

### 5. daemon 起動コマンドの組み立て

scheduler ファイルは生成しない。代わりに、適用ステップで直接実行する tmux コマンドを組み立ててプレビューする:

```bash
DAEMON_CMD="ralph-crew daemon --interval ${DAEMON_INTERVAL} --config ${PROJECT}/.claude/crew.json"
TMUX_WINDOW_NAME="scheduler"
```

`ralph-crew init` が tmux session `ralph-crew` を作成する。そこへ専用 window (`scheduler`) を追加し、daemon を exec させる。

### 6. プレビュー + 確定確認

生成された `crew.json.preview` を diff (既存との比較、無ければ全文) で見せ、daemon 起動コマンドを併記し、最後に AskUserQuestion:

| header | question | options |
|--------|----------|---------|
| Apply | 上記内容で書き込みますか? | 1. 書き込む & `ralph-crew init` + daemon を tmux window で起動して即時発火検証する **(Recommended)** / 2. crew.json だけ書き込む (init/daemon は手動) / 3. キャンセル |

### 7. 適用

**Option 1 (書き込み + 検証)**:

```bash
mv "$PROJECT/.claude/crew.json.preview" "$PROJECT/.claude/crew.json"
CONFIG="$PROJECT/.claude/crew.json"

# 1. worker を起動 (tmux session ralph-crew を idempotent に作成)
ralph-crew init --config "$CONFIG"

# 2. daemon 用 window を作成。既存なら kill して作り直す (設定変更反映のため)
if tmux list-windows -t ralph-crew -F '#{window_name}' 2>/dev/null | grep -Fx "scheduler" >/dev/null; then
  tmux kill-window -t "ralph-crew:scheduler"
fi
tmux new-window -d -t ralph-crew -n scheduler \
  "exec ralph-crew daemon --interval ${DAEMON_INTERVAL} --config '${CONFIG}'"

# 3. 即時発火の目視確認 (数秒後に log に dispatch 行が出るはず)
sleep 3
tail -n 20 "/tmp/ralph-crew/${PROJECT_NAME}/logs/dispatch.log" 2>/dev/null || true
ralph-crew status --config "$CONFIG"
```

- `tmux list-windows -t ralph-crew` で `scheduler` window の存在を確認
- `tail -f /tmp/ralph-crew/${PROJECT_NAME}/logs/dispatch.log` で daemon 動作をリアルタイム監視

**Option 2 (書き込みのみ)**:

```bash
mv "$PROJECT/.claude/crew.json.preview" "$PROJECT/.claude/crew.json"
```

次のステップとして `ralph-crew init` → `tmux new-window ... ralph-crew daemon ...` のコマンドを案内する。

**Option 3 (キャンセル)**:

`.preview` ファイルを残したまま中断 (再開時に diff レビュー可能)。

### 8. 完了報告

成功時に以下を表示:

- 設置パス: `$PROJECT/.claude/crew.json`
- tmux session/window: `ralph-crew:scheduler` で daemon が常駐
- pidfile: `/tmp/ralph-crew/${PROJECT_NAME}/daemon.pid`
- 観察コマンド
  - `tmux attach -t ralph-crew`
  - `tail -f /tmp/ralph-crew/${PROJECT_NAME}/logs/dispatch.log`
  - `ralph-crew status --config "$PROJECT/.claude/crew.json"`
- 撤去コマンド
  ```bash
  # daemon を停止 (pidfile の pid に TERM を送るか、tmux window を kill)
  tmux kill-window -t ralph-crew:scheduler 2>/dev/null || true
  [[ -f /tmp/ralph-crew/${PROJECT_NAME}/daemon.pid ]] \
    && kill -TERM "$(cat /tmp/ralph-crew/${PROJECT_NAME}/daemon.pid)" 2>/dev/null || true

  # worker + state を一括撤去
  ralph-crew teardown --config "$PROJECT/.claude/crew.json"
  ```

## エッジケース

- **既存 daemon が走っている**: pidfile が生きている場合は `cmd_daemon` 自体が多重起動を拒否するため、まず `tmux kill-window -t ralph-crew:scheduler` または `kill -TERM $(cat .../daemon.pid)` を案内してから再セットアップ
- **tmux session `ralph-crew` が既存**: `ralph-crew init` は idempotent (session/worker は has-session/window-exists チェック) のためそのまま再実行可
- **tmux server が死んで復活した直後**: tmux-continuum が session layout を復元するが、daemon process 自体は再起動されない。`@resurrect-processes` に `'~ralph-crew daemon'` を追加すればコマンドも自動復活 (別件の拡張)
- `gh auth status` 失敗 → `gh auth login` 案内して中断
- origin 無し / push 認証 NG → fix モード選択時のみ致命、issue-only / none なら警告のみで続行
- カレントディレクトリが git repo でない → 致命 (ralph-crew は worktree を要求するため)
- `.claude/crew.json` が既存 → 上書き確認 (diff 提示)

## 注意事項

- **外部 scheduler 非依存**: launchd / cron / systemd のいずれにも依存しない。dotfiles 完結で動くことがこのスキルの前提
- **daemon は tmux window 常駐**: 同じ tmux session (`ralph-crew`) の `scheduler` window で動く。attach して `Ctrl-C` すれば止められる
- **pidfile による多重起動ガード**: `${STATE_DIR}/daemon.pid`。stale pidfile (プロセスが死んでいる場合) は cmd_daemon 側で自動除去
- **tick と per-task interval の関係**: Q6 の daemon tick は数分未満が推奨 (最短タスクより十分短く)。tick が大きすぎると per-task interval を下回れない
- **AskUserQuestion をブロックする hook を追加してはならない**: このスキルは対話前提
- **生成した crew.json は .gitignore 対象が多い**: dotfiles では `.claude/crew.json` を gitignore している。プロジェクト側の方針に合わせるよう案内 (commit するなら secrets を含めない)
- **fix モードを選んだ場合は実 PR が作成される**: パブリックリポジトリでは特に最初は issue-only から始めることを Q4 の Recommended に反映
