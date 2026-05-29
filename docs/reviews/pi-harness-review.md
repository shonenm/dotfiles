# pi エージェントハーネス レビュー (2026-05-29)

対象: `common/pi/.pi/agent/`（settings.json, AGENTS.md, APPEND_SYSTEM.md, extensions/*.ts, skills/, prompts/）+ `docs/specs/agent-infrastructure.md`

Web BP 調査の根拠は本文末尾の References 参照。

---

## 全体評価

設計思想は良質。特に以下は BP に合致:

- spec-driven (specify once / implement natively)。symlink 共有を避け仕様共有にした判断は妥当（参照記事の失敗事例回避）。
- 監査ログ (audit.log.jsonl / mcp-audit.jsonl)、stats、citation 永続化。
- web research の search→fetch→cache→cite プロトコル。
- secret パターンガード (web-tools の checkSecrets)。
- skill の progressive disclosure（frontmatter description + 本文）。
- レイヤ分離 (extension = 機構, skill = ワークフロー, prompt = テンプレート)。

一方で、実装と仕様・ドキュメントの drift、shell-out のセキュリティ、権限機構の未完成が複数ある。以下、深刻度順。

---

## Critical（セキュリティ）

### C1. web-tools: コマンドインジェクション

`jinaFetch` / `rawFetch` / `jinaSearch` が LLM 提供の URL/クエリを単一引用符シェル文字列へ生補間し `execSync` 実行。

```ts
`curl ... '${JINA_FETCH_URL}/${url}'`   // url 未エスケープ
`curl -fsSL --max-time 15 -L '${url}'`  // 同上
```

`web_fetch` の検証は `startsWith("http")` のみ。URL に単一引用符を含めると引用符を脱出して任意コマンド実行可能:

```
url = https://a/'$(touch /tmp/pwned)'   → startsWith 通過 → RCE
```

BP（OWASP / Node docs）: シェル文字列を組み立てない。`execFile('curl', [..., url])`（arg 配列, shell なし）か、curl を捨てて native `fetch`/`undici` を使う。`shell:true` + arg 配列は無効（Node が連結してシェル解釈に戻る）ので不可。

→ 修正: web-tools 全 fetch/search を `execFile` か `fetch` へ。最低でも arg 配列化。

### C2. protected-paths: アンカー付き正規表現が機能していない

```ts
const raw = JSON.stringify(event.input ?? {});
const matched = PROTECTED_PATTERNS.find((p) => p.test(raw));
```

`event.input` 全体を JSON 文字列化してテストするため:

- `/^\.env/` `/^\.env\./` — JSON は `{` で始まる → 先頭アンカー一致せず → 永久に不発。
- `/\.pem$/` `/\.key$/` `/\.p12$/` `/\.pfx$/` — `$`（文字列末尾）は JSON 末尾 `}` を見る → 永久に不発。

つまり `.env`, 秘密鍵 (.pem/.key/.p12/.pfx) への write がブロックされない。仕様の主旨（機密ファイル保護）が破綻。さらに path ではなく content も含む JSON 全体を検査するため、内容に "secrets." 等を含むだけの正当な write を誤ブロックする副作用もある。

→ 修正: `event.input` から実際の path フィールド（file_path / path）を取り出し、その文字列のみをテスト。アンカーは path に対して評価する。

### C3. MCP "ask" 権限が未実装（黙ってallow）

```ts
if (permission === "ask") {
  // TODO: integrate with ctx.ui.confirm when available in tool context
}
```

spec / AGENTS.md / mcp-research skill は allow/ask/deny の3段階を「実装済み (✅)」と記載。実際は ask = allow。playwright 等 ask 設定サーバが無確認実行される。

BP 調査の裏付け: pi の `ctx.ui.confirm` は `tool_call` イベントの ctx でのみ対話可能。`registerTool().execute()` には対話 UI が渡らない（-p モードでは confirm()→false）。よって execute 内での確認は構造的に不可能。

→ 修正: MCP ツール（`mcp_*`）に対し `tool_call` イベントハンドラを登録し、そこで permission を引いて ask なら `ctx.ui.confirm`、deny なら block。permission-gate.ts と同じ機構へ統合できる。spec の Status 表は ask 未完を反映して訂正。

### C4. web_fetch に SSRF ガードなし

任意 URL を fetch 可能。`169.254.169.254`（クラウドメタデータ→IAM 資格情報窃取）、`localhost`/RFC1918 内部 IP、リダイレクト経由内部到達を防げない。

→ 修正（OWASP SSRF Cheat Sheet）: https 限定 + ホスト名解決後に private/loopback/link-local レンジを拒否、リダイレクト毎に再検証（`-L` 自動追従をやめ手動再チェック）。共有ヘルパ化して mcp/web 双方で使用。

---

## High（正しさ・整合性）

### H1. agent-delegation: task が引用符で囲まれていない

```ts
return `sh -c 'pi --model ${m} -p ${shellSafe(task)} < /dev/null'`;
```

`shellSafe` は単一引用符を `'\''` へ正しくエスケープ（→外側引用符の脱出は防げており、インジェクションは概ね回避）。だが task 自体が引用符で囲まれていないため、複数語タスクは `pi` に複数引数として渡り破綻する。`-p '<task>'` のように内側でも quote が必要。加えて `${m}`（model パラメータ, LLM 制御可）は生補間で、単一引用符を含むと脱出余地あり。

→ 修正: arg 配列で `spawn('pi', ['--model', m, '-p', task])`。pueue も `pueue add -- pi --model m -p <task>` を arg 配列で。

### H2. mcp-gateway: required パラメータが必須化されない

```ts
props[key] = Type.Optional(Type.String(...));  // 全プロパティ Optional
...
if (tool.inputSchema.required) required.push(...);  // 計算するが
const schema = Type.Object(props as any);          // required を使っていない
```

`required` 配列を集めるが TypeBox スキーマに反映していない。全 MCP ツール引数が optional 扱いになり、LLM が必須引数を省略→ツールエラー多発。

→ 修正: required に含まれるキーは `Type.Optional` を外す（非 optional で登録）。

### H3. skill が存在しないツールを参照

- `deep-research`: `web_fetch_many`（未実装）
- `docs-research`: `web_search_docs(...)`（未実装）
- `github-research`: `web_search_github`, `web_clone_github`（未実装）

web-tools.ts が提供するのは `web_search`, `web_fetch`, `web_cache_lookup/write`, `web_citation_add/list` のみ。BP 調査でも「存在しないツールを参照する skill は hallucinate-and-fail / 出力捏造を招く」アンチパターンと明示。

→ 修正: 各 skill の手順を実在ツール名へ書き換え。docs/github 検索は `web_search` + クエリ修飾（`site:` / "official documentation"）で表現。github-research の git clone 部分は実在の bash 手順なので維持可。

### H4. MCP config パスの不一致

- spec / AGENTS.md: `~/.config/agent/mcp.json`
- mcp-gateway.ts (loadConfig): `~/.config/mcp/mcp.json`

ドキュメント通りに置くと読み込まれない。

→ 修正: どちらかに統一。共有 config を謳うなら spec 側 (`~/.config/agent/mcp.json`) に合わせるのが筋。

### H5. APPEND_SYSTEM.md が web ツールを使わせない

```
## Web Access Fallback
- Pi has no built-in WebSearch/WebFetch. Use Jina AI via bash tool:
  - WebFetch: curl -fsSL 'https://r.jina.ai/<URL>'
```

web-tools.ts が `web_search`/`web_fetch` を登録しているのに、system prompt は「組み込みが無いので curl を使え」と指示。モデルが cache/cite/secret-guard 付きの正規ツールチェーンを迂回し生 curl に流れる。pi コア組み込みが無いのは事実だが、拡張で提供済みである点を反映していない。

→ 修正: 「web_search / web_fetch ツールを使う。curl は最終フォールバックのみ」へ書き換え。

### H6. memory_search が過去 daily を検索しない

description は「across all memory files (MEMORY.md, daily logs)」だが、実装は MEMORY.md と当日 daily のみ。過去ログがヒットしない。

→ 修正: DAILY_DIR を走査して全 daily を対象に。件数が増えたら qmd/semantic へ。

---

## Medium

### M1. MCP protocolVersion が2世代古い

`"2024-11-05"` 固定。現行は `2025-11-25`（間に 2025-03-26 / 2025-06-18）。

→ 修正: 最新を送り、サーバ応答の version を受け入れるネゴシエーション方式へ（固定文字列をやめる）。stdio のままで可（SSE は 2025-03-26 で deprecated、stdio はローカル推奨のまま）。リモート対応時のみ Streamable HTTP を追加。

### M2. permission-gate の穴

- `/\b DROP\s+/i` `/\b DELETE\s+FROM\s+/i` — `\b` 直後に空白リテラルがあり、典型 SQL（"DROP TABLE", "; DROP")にマッチしない（バグ）。
- `bash` ツールのみ対象。他の実行系ツールは素通り。
- 危険パターン不足: `dd`, `mkfs`, `> /dev/sd`, `curl|sh`/`wget|sh`, `git clean -fdx`, `git push --force-with-lease`, fork bomb 等。
- denylist 方式は本質的に回避可能（`rm -r -f`, base64 等）。defense-in-depth と割り切り、これを唯一の境界にしない旨を明記すべき。

→ 修正: SQL 正規表現修正、パターン追加、対象ツール拡張、限界の明文化。

### M3. 軽微な実装品質

- mcp-gateway: `session_start` ハンドラを2回登録（initialize 内で reloadConfig 済みのため2つ目は冗長）。
- agent-delegation: `fallbackModels` は定義のみで未使用（dead code）。high tier コメントは「gpt-5.5」だがコードは kimi-k2.6（doc drift）。
- statusline: render 毎に `getBranch()` 全 message を再走査してトークン合計（大セッションで重い）。turn_end でキャッシュ可。mode が起動間で永続化されない。
- session-manager: `modified` を `entry.name.slice(0,19)` でファイル名先頭がタイムスタンプ前提（脆い）。mtime 使用が堅牢。

### M4. アーキテクチャ: 自作とコミュニティ package の重複

settings.json は `npm:pi-subagents` を入れつつ、custom `agent-delegation.ts` も持つ。pi エコシステムには `pi-mcp`/`pi-mcp-adapter`（lazy connect, tool metadata cache, stdio/SSE/HTTP）、`pi-web-access` も存在。自作 mcp-gateway / web-tools は再発明の側面。

→ 判断: 「自作の付加価値（pueue 非同期、difficulty tier、secret guard、audit）」を維持する部分と、保守をコミュニティに委ねる部分を切り分ける。最低でも pi-subagents と agent-delegation の役割重複は AGENTS.md で整理（現状も触れているが、どちらをデフォルトにするか不明確）。

### M5. memory の無制限成長

MEMORY.md は append-only、キュレーション/上限なし。肥大化で session_start injection（最大 8K だが中央 truncation）の質が劣化。BP: 取捨選択して書く、daily は当日+前日ロード、injection は選択的に。memory は indirect prompt injection 経路（注入内容のサニタイズ推奨）。

### M6. stdio-only MCP

リモート/HTTP MCP サーバを使えない。現状は許容範囲だが将来制約。追加時は SSE でなく Streamable HTTP。

---

## Low / polish

- 監査ログが MCP 引数 (argsSummary) を記録 → 秘密が引数に乗ると漏れる。secret パターンで redact 推奨。
- web_search の `num` パラメータは jina backend で無視（searxng のみ 10 件 slice）。
- spec の Implementation Status 表が全 ✅（ask 未完を過大表示）。
- AGENTS.md 冒頭の spec 参照が相対パス `docs/specs/...`（ユーザスコープ ~ から解決しない可能性）。

---

## 改善提案（修正以外の上積み）

1. 権限機構の統合: permission-gate / protected-paths / MCP ask を `tool_call` イベントの単一ゲートに集約。protected-paths は path 解析ベースへ、MCP は ask→confirm を実現。
2. web research 強化: (a) content-hash でキャッシュ dedup + 矛盾検出、(b) volatility 別 fetch_policy（時事は live、安定は cache）、(c) 重要 claim の adversarial 再検証ツール、(d) citation に source version/claim trace。
3. SSRF/インジェクション共有ヘルパ: URL 検証（scheme/IP レンジ）と arg 配列実行を util 化し web/mcp 双方で使用。
4. memory: 上限 + キュレーション + 前日ログ同時ロード + 注入内容サニタイズ。
5. observability: 既存 audit を OTel/構造化ログへ拡張（PreToolUse intent / PostToolUse result / PreCompact lost-context）。
6. tool 数管理: MCP gateway がツールを大量登録すると 30-40 超で LLM のツール選択精度が落ちる。lazy load / フィルタを検討。
7. AGENTS.md スリム化: 現状は良好だが、self-host する詳細手順は skill/別ファイルへ progressive disclosure。

---

## UX 改善アイデア評価 (2026-05-29)

pi ネイティブ機能を調査し、「再発明を避ける」観点で評価。

### remote-control — 実装不要（導入済み）

pi-remote-control 導入済 (settings.json packages, commit 19455a9)。`/remote-control-pair`, `/remote-control` 稼働。新規実装不要。付加価値の方向性: permission-gate の confirm をモバイルへ転送して remote 承認、sub-agent 完了のモバイル通知。

### /goal /usage /clear — 大半が再発明

- `/clear` → pi 標準 `/new`（新セッション）。作らない。
- `/usage` `/cost` → pi 標準 footer + `/session` が token/cache/cost/context/model を表示済み。`statusline.ts` も同情報を再描画しており既に二重。作らない。statusline の独自価値は web/mcp stats 行 + gauge のみと割り切る。
- `/goal` → 標準になし。唯一作る価値あり。ただし `memory.ts` の scratchpad と機能重複 → 単独コマンドでなく memory 拡張として実装（pinned goal を毎ターン injection + widget 表示）。pi の todo example 拡張を参考に。

### sub-agent 状況表示 — 作る価値高、要アーキ判断

`agent-delegation.ts` は pueue で detached な別プロセス `pi -p` を起動 → main session の `tool_execution_*` イベントは飛ばない。イベント駆動 live widget は現行非同期モデルでは不可。

- 案A（async 維持・推奨）: `delegate_agent` が状態を `~/.pi/research/active-agents.json` に書込 (queue/start/done/taskId) → footer か widget が `readStats` と同じ TTL キャッシュでポーリング表示（running/queued/done 件数 + task名）。安価・現行設計に合う。
- 案B（in-process 化）: sync registerTool or `pi-subagents` 採用 → `tool_execution_start/update/end` + `setWidget` で Claude 並み live ストリーム。pueue background 性を失う。

表示は footer に詰めず `ctx.ui.setWidget(id, fn, {placement:"aboveEditor"})` 推奨。

## 修正計画

優先: Critical (C1–C4) を先行実装。UX 追加（/goal, sub-agent widget）はその後。

| ID | 内容 | 対象 | 方針 |
|----|------|------|------|
| C1 | コマンドインジェクション | web-tools.ts | `execSync` シェル文字列 → `execFileSync` arg 配列 |
| C2 | protected-paths 不発 | protected-paths.ts | path フィールド抽出して検査、アンカーを path に対し評価 |
| C3 | MCP ask 未実装 | mcp-gateway.ts | `mcp_*` を `tool_call` ゲートで ask→confirm / deny→block |
| C4 | SSRF | web-tools.ts | host 解決→private/loopback/link-local 拒否、scheme 限定 |

注: pi 拡張のローカル型定義 (`@earendil-works/pi-coding-agent`) は未インストールのため静的型チェック不可。実装は既存パターン準拠で行い、純粋ヘルパは個別検証。pi 実行下での E2E 確認は別途必要。

## References (Web BP 調査)

- pi extensions: https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md , https://pi.dev/ , pi-subagents / pi-mcp / pi-mcp-adapter / pi-web-access / pi-remote-control
- MCP: spec 2025-11-25 changelog, versioning, transports, security_best_practices (modelcontextprotocol.io); Simon Willison "MCP prompt injection"; Microsoft mcp-best-practices
- Harness BP: agentsmd.io, GitHub "how to write a great AGENTS.md", Anthropic "Agent Skills" engineering + best-practices, LangChain "context engineering for agents", Unit42 "memory poisoning", harness-engineering-best-practices-2026
- shell/SSRF: Node.js child_process docs, nodejs/node#57143, OWASP SSRF Prevention Cheat Sheet, OWASP A10:2021
