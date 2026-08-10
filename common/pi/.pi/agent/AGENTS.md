# AGENTS.md (User Scoped)

## Canonical docs

- Project rules: `~/dotfiles/CLAUDE.md`
- pi usage: `~/dotfiles/docs/ai-agents/pi/`
- pi implementation: `~/.pi/agent/extensions/`

## Shared configuration

- `~/.config/agent/skills/` — Agent Skills Standard; shared skillの正本
- `~/.config/agent/knowledge/` — 横断原則の参照資料（自動注入ではない）
- `~/.config/agent/mcp.json` — pi / Command Code用MCP設定。Claude MCPは別設定

## Execution rules

- 長時間・background commandはpueueを使う。
- secret、credential、`.env`、private key、production dumpを読まない。
- 生成物とruntime fileを直接編集しない。
- root causeを確認し、既存実装・stdlib・native機能を優先する。
- agentはセッション開始時のworking tree（main repositoryまたは既存worktree）で実装し、利用者の明示なしに別worktreeへ移動しない。
- agentは`git worktree add`や`pnpm wt provision`でworktree capacityを追加しない。追加が必要なら利用者がterminalから実行する。

## Memory

- `memory_write`, `memory_read`, `memory_search`, `scratchpad` を使う。
- 長期情報は `MEMORY.md`、作業中メモはdaily、checklistは `SCRATCHPAD.md`。
- `/pin-goal` は軽量context、完了まで自走する作業は `/goal`。

## Goal / loop / monitor

- 有限の実装完了条件には `/goal` を使う。
- `/loop` / `LoopCreate` は時間間隔に意味がある観測・pollingだけに使う。
- 長時間commandは `MonitorCreate`、通常のbackground processはpueueを使う。

## Delegation

- 利用者がdelegation、subagent、workflow、並列調査、またはmulti-agent reviewを明示した場合だけ委譲する。品質向上だけを理由に自動委譲しない。
- advisory / explorationは `subagent`（pi-subagents）。`subagent` と `workflow` の子モデルは設定済みの gpt-5.4-mini:medium を使い、呼び出し時に `model` を指定しない。
- pueue backgroundとdifficulty tierが必要な場合だけ `delegate_agent`。
- `delegate_agent` のtierは `high`: gpt-5.6-sol、`medium`: gpt-5.4-mini、`low`: gpt-5.3-codex-spark。
- reviewは原則1 passとし、reviewerの提案を新しい要件として扱わない。再reviewは利用者が明示した場合だけ行う。
- Piの`web_search`が利用不能なら、利用者がWeb調査を依頼した場合に限り、共有`deep-research` skillに従いCodex native searchへephemeral委譲する。
- 同じworking treeへ複数writerを置かない。reviewer / scoutはread-onlyにする。

## Workflow

`workflow` は利用者が明示的にopt-inした広いaudit、fan-out research、multi-perspective reviewだけに使う。単一ファイルの小変更や通常の実装検証には使わない。

## pi-specific extensions

- `permission-gate.ts` — dangerous shell commandの確認
- `protected-paths.ts` — secret / generated path保護
- `web-tools.ts` — SearXNG + Jina、cache、citation、SSRF guard
- `mcp-gateway.ts` — stdio MCP bridge。認可はpi-permission-system
- `memory.ts` — Markdown memory
- `agent-delegation.ts` — pueue delegation
- `statusline.ts` — session / background activity表示

Community packageが同じ保証を満たす場合はcustom実装を削除して採用する。remote MCPの実需要が出るまでStreamable HTTPは追加しない。
