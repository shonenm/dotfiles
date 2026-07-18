# pi-coding-agent 改善計画 (2026-07)

目的: pi-coding-agent 0.80.6 時点の実装・設定を、現行の Pi extension / package / project trust の best practice に寄せる。PR 単位で小さく切り、上から順に loop 実行できる形にする。

## 前提

- Pi: `@earendil-works/pi-coding-agent 0.80.6`
- dotfiles 管理: `common/pi/.pi/agent/`
- 実ランタイム: `~/.pi/agent/`
- version control: `git status` / `git diff` を使う
- 既存作業がある場合は巻き込まない。各 PR の開始前に `git status` で差分を確認する。

## 現状の重要 findings

| 優先度 | Finding | Evidence | 方針 |
| --- | --- | --- | --- |
| P0 | Web search が SearXNG の実ポートと不一致 | `web-tools.ts`: `localhost:8899`; `docker-compose.searxng.yml`: `127.0.0.1:8888:8080` | まず `8888` に修正 |
| P0 | dotfiles と実ランタイムが drift | `common/.../extensions` に `permission-gate.ts`, `prompt-stash.ts` があるが `~/.pi/agent/extensions` にはない | 使う/消すを明確化 |
| P0 | Permission 層が重複 | `pi-permission-system` + `protected-paths.ts` + 未ロード `permission-gate.ts` | `pi-permission-system` を正本に寄せる |
| P1 | MCP project config が trust 境界を見ていない | `mcp-gateway.ts` が `.mcp.json` / `.pi/mcp.json` を無条件 read | `ctx.cwd` + `ctx.isProjectTrusted()` に変更 |
| P1 | Plan mode が active tool set を破壊 | `NORMAL_MODE_TOOLS = ["read", "bash", "edit", "write"]` | enable 前の active tools を復元 |
| P1 | Memory context が session に蓄積しうる | `session_start` で `pi.sendMessage(... nextTurn)` | `before_agent_start` injection へ寄せる |
| P2 | Subagent 実装が二重化 | 自前 `agent-delegation.ts` / `workflow.ts` と package `pi-subagents` | 自前を薄くする/削る |
| P2 | Session manager が本体機能と重複 | `/name`, `/resume`, `/export`, `/import` は Pi 本体に存在 | auto-name 以外を削る |
| P2 | spec が現状と矛盾 | `agent-infrastructure.md` の memory/model tier/番号/実装状況 | 実装修正後に更新 |

## Loop 実行ルール

各 PR はこの順で進める。

```bash
git status
# 対象 PR の Scope だけ実装
git diff
# smoke / relevant tests
git commit -m "<type>(pi): <summary>"
# 必要なら PR 化
```

共通 smoke:

```bash
pi --version
pi --list-models opencode-go | head
pi --mode json --no-session --no-extensions --model opencode-go/deepseek-v4-flash:off -p 'say ok'
```

## PR backlog

### PR-01: Web research の SearXNG port 修正

**Goal**: `web_search` がローカル SearXNG を実際に使える状態に戻す。

**Scope**

- `common/pi/.pi/agent/extensions/web-tools.ts`
  - `SEARXNG_URL` を `http://localhost:8888` に修正
- 必要なら `docs/ai-agents/pi/web-research.md` のポート表記を確認・修正

**Checks**

```bash
curl -fsS --max-time 10 'http://localhost:8888/search?q=pi-coding-agent&format=json' >/tmp/searxng.json
pi --mode json --no-session --model opencode-go/deepseek-v4-flash:off -p 'web_search tool が SearXNG を使えるか、web_search("pi-coding-agent", num=1) で確認して結果だけ短く報告'
```

**Acceptance**

- `web_search` が `All search backends failed` にならない
- 結果 backend が `searxng` になる

---

### PR-02: Pi runtime/dotfiles drift の解消

**Goal**: dotfiles にあるもの = 実際にロードされるもの、という状態に戻す。

**Scope**

- `~/.pi/agent/extensions` と `common/pi/.pi/agent/extensions` の差分を整理
- `permission-gate.ts`: `pi-permission-system` に寄せるなら削除、残すなら stow/symlink を復旧
- `prompt-stash.ts`: 使うなら stow/symlink を復旧、使わないなら削除
- `~/.pi/agent/extensions/pi-command-code/` と `npm:pi-commandcode-provider` の二重化を解消

**Checks**

```bash
comm -3 \
  <(find common/pi/.pi/agent/extensions -maxdepth 1 -type f -name '*.ts' -exec basename {} \; | sort) \
  <(find ~/.pi/agent/extensions -maxdepth 1 \( -type f -o -type l \) -name '*.ts' -exec basename {} \; | sort)
pi list
pi --list-models command-code | head
```

**Acceptance**

- 管理外 extension が残っていない、または明示的に docs に理由がある
- Command Code provider が一つだけロードされる

---

### PR-03: Permission system 一本化

**Goal**: permission policy の正本を `pi-permission-system` + `pi-permissions.jsonc` に寄せ、自前 denylist の重複を減らす。

**Scope**

- `common/pi/.pi/agent/pi-permissions.jsonc`
  - `tools.* = allow` をやめ、未知 tool は `ask` に戻す
  - read-only 系 (`read`, `grep`, `find`, `ls`, `web_cache_lookup`, `web_citation_list`, `memory_read`, `memory_search`) は `allow`
  - write/edit/bash/delegation/mcp は必要最小限で `ask`
- `permission-gate.ts` / `protected-paths.ts` の扱いを決める
- `common/pi/.pi/agent/AGENTS.md` の Extensions 説明を実態に合わせる

**Checks**

```bash
pi --mode json --no-session --model opencode-go/deepseek-v4-flash:off -p 'read tool で README.md を読むだけ実行してよいか確認'
pi --mode json --no-session --model opencode-go/deepseek-v4-flash:off -p 'edit tool は使わず、編集が必要そうな場合に確認が必要とだけ答えて'
```

**Acceptance**

- read-only 操作は不要に止まらない
- write/edit/bash の危険操作は自動許可されない
- AGENTS.md と実ロード extension が一致

---

### PR-04: MCP Gateway を project trust 対応にする

**Goal**: project-local MCP config を Pi の trust 境界に合わせる。

**Scope**

- `common/pi/.pi/agent/extensions/mcp-gateway.ts`
  - `process.cwd()` 固定をやめ、`ctx.cwd` を使う
  - `~/.config/agent/mcp.json` は常に読む
  - `.mcp.json` / `.pi/mcp.json` は `ctx.isProjectTrusted()` のときだけ読む
  - startup で壊れた MCP server があっても headless run を長くブロックしない
- 必要なら `docs/ai-agents/pi/mcp-layer.md` 更新

**Checks**

```bash
pi --mode json --no-session --no-approve --model opencode-go/deepseek-v4-flash:off -p 'say ok'
pi --mode json --no-session --approve --model opencode-go/deepseek-v4-flash:off -p 'say ok'
```

**Acceptance**

- `--no-approve` で project-local MCP config を読まない
- global MCP config は引き続き有効
- 壊れた MCP server があっても agent run が終了できる

---

### PR-05: Plan mode の active tools 復元

**Goal**: plan mode を抜けた後、extension tools を落とさない。

**Scope**

- `common/pi/.pi/agent/extensions/plan-mode/index.ts`
  - plan mode enable 前の `pi.getActiveTools()` を保存
  - disable / execute / complete 時に保存した active tools を復元
  - 最新 Pi example の「active custom tools preserve」差分だけ取り込む

**Checks**

```text
/plan
# plan mode on/off
# off 後に extension tools が消えていないことを確認
```

**Acceptance**

- `/plan` off 後に `web_search`, `memory_read`, `subagent` 系 tools が消えない
- read-only 中の bash allowlist は維持

---

### PR-06: Memory context injection の重複防止

**Goal**: memory context が session に蓄積し続けないようにする。

**Scope**

- `common/pi/.pi/agent/extensions/memory.ts`
  - `session_start` の `pi.sendMessage(memory-context)` をやめる
  - `before_agent_start` でそのターン用の hidden message を返す
  - `/goal` set 時も次ターン注入の重複を避ける

**Checks**

```bash
pi --mode json --no-session --model opencode-go/deepseek-v4-flash:off -p 'memory_read は呼ばず say ok'
```

**Acceptance**

- session_start ごとに memory-context message が永続追加されない
- 起動後の通常 turn では memory/scratchpad/goal が引き続き context に入る

---

### PR-07: quick-question を shell-free / no-extension にする

**Goal**: `/btw` を安全・軽量にする。

**Scope**

- `common/pi/.pi/agent/extensions/quick-question.ts`
  - `execSync` shell string を `execFile` / `execFileSync` arg array に変更
  - child pi は `--no-session --no-extensions` を付け、MCP/Web startup などを避ける

**Checks**

```text
/btw 1+1だけ答えて
```

**Acceptance**

- quote を含む質問でも shell injection しない
- 30 秒以内に返る

---

### PR-08: Subagent 実装の整理

**Goal**: `pi-subagents` と自前 delegation/workflow の責務を分ける。

**Scope**

- `common/pi/.pi/agent/extensions/agent-delegation.ts`
- `common/pi/.pi/agent/extensions/workflow.ts`
- `common/pi/.pi/agent/AGENTS.md`

選択肢:

1. `pi-subagents` を正本にして自前を削除
2. pueue label/statusline だけ残す薄い adapter に縮小
3. 現状維持。ただし docs に「なぜ package では足りないか」を明記

推奨は **2**。

**Checks**

```bash
pi list
pi --mode json --no-session --model opencode-go/deepseek-v4-flash:off -p 'subagent は起動せず、利用可能な delegation 方針を一文で説明'
```

**Acceptance**

- AGENTS.md の delegation 説明が実態と一致
- 同じ目的の tool が過剰に並ばない

---

### PR-09: Session manager を削る

**Goal**: Pi 本体の session 機能と重複する自前実装を減らす。

**Scope**

- `common/pi/.pi/agent/extensions/session-manager.ts`
  - 残す: git branch による auto session name
  - 削る候補: `/sessions`, `/session-export`, `/session-import`, `/session-name`
- `AGENTS.md` の Session Management 記述を Pi 本体コマンドに寄せる

**Checks**

```bash
pi --mode json --no-session --model opencode-go/deepseek-v4-flash:off -p 'say ok'
```

**Acceptance**

- 本体機能で代替できる command が docs から消えている
- auto-name が必要なら維持される

---

### PR-10: Spec / docs の最終同期

**Goal**: 実装と docs/spec を一致させる。

**Scope**

- `docs/specs/agent-infrastructure.md`
  - component numbering 修正
  - Memory storage の実態を Markdown に更新、または実装に合わせる
  - Agent Delegation model tier を AGENTS.md / 実装と一致
  - Permission/MCP/Web の正本を更新
- `docs/ai-agents/pi/*.md`
  - 変更後の実態に合わせる
- `docs/INDEX.md`
  - 必要なリンク追加

**Checks**

```bash
rg '8899|permission-gate|localhost:8888|Memory Persistence|Agent Delegation' docs common/pi/.pi/agent/AGENTS.md
git diff --stat
```

**Acceptance**

- docs が実装と矛盾しない
- 次回 agent がこの計画なしでも構成を理解できる

## Deferred / やらないこと

- MCP Streamable HTTP 対応: remote MCP が実需要になるまでやらない
- web-tools 全面置換: まずポート・SSRF・cache/citation の小修正で十分
- custom provider の自作継続: package 版が動くなら package に寄せる
- plan mode の巨大化: Pi 本体思想に反するので、必要最小限に留める
