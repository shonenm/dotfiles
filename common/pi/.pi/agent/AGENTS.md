# AGENTS.md (User Scoped)

## Infrastructure Spec

The canonical specification for all agent infrastructure components is at:
`~/dotfiles/docs/specs/agent-infrastructure.md` (in the dotfiles repo).

Implementations:
- **Pi**: `~/.pi/agent/extensions/` (TypeScript)
- **Claude Code**: `~/.claude/hooks/` (shell scripts)

## Shared Configuration

Tool-agnostic config is in `~/.config/agent/`:
- `mcp.json` — MCP server config (shared across Claude and pi)
- `skills/` — Agent Skills Standard (github, research, quality, debug)
- `knowledge/` — Shared principles (communication, security, web-research)

## Version Control

When `.jj/` exists in a repository, use Jujutsu (`jj`) as the default version-control write layer.

- Run `jj status` before editing to snapshot and inspect state.
- Use `jj status` / `jj diff` / `jj log` for state and review.
- Prefer jj change IDs over Git hashes when referring to local work.
- Use `jj describe -m "<message>"` to name the current change.
- Use `jj new` when the current logical change is done.
- Clean up agent-made messy history with `jj split` / `jj squash` / `jj describe`.
- Recover with `jj undo`, or `jj op log` → `jj op restore <op>` when needed.
- Bookmarks are not active branches; create or move them only when pushing.
- Push to GitHub with `jj git push --change @-` or an explicit bookmark.
- In `.jj/` repos, avoid mutating Git commands such as `git commit`, `git add`, `git reset`, `git checkout`, `git rebase`, and `git clean`; read-only Git commands are OK.

## Skills

Invoke via `/skill:<name>`. Shared skills are auto-discovered from `~/.config/agent/skills/`.
Claude-specific skills under `~/.claude/skills/` are also available.


Use `pueue` for background processes: `pueue add -- <command>`

## Extensions

- `permission-gate` — blocks dangerous bash commands
- `protected-paths` — blocks writes to secrets and generated files
- `web-tools` — search, fetch, cache, citation (SearXNG + Jina)
- `mcp-gateway` — MCP tool bridge with permission control and audit
- `statusline` — footer with token stats, context, git branch, research activity

## Custom vs Community Packages

These extensions are maintained in-house (`~/.pi/agent/extensions/`) rather than
adopting community packages (`pi-mcp`, `pi-web-access`, `pi-subagents`) because
they add value the packages don't: pueue-based async delegation with
difficulty-tiered model selection (`agent-delegation`), secret/SSRF guards +
cache/citation audit trail (`web-tools`), and unified allow/ask/deny gating with
audit logging (`mcp-gateway`). When a community package gains equivalent
guarantees, prefer adopting it over maintaining the custom one.

- `mcp-gateway` transport: **stdio only**. SSE is deprecated upstream; Streamable
  HTTP support is intentionally deferred until a remote MCP server is actually
  needed (avoid speculative implementation). stdio is the recommended local transport.

## Memory

- Persistent across sessions via plain Markdown files in `~/.pi/agent/memory/`
- Tools: `memory_write`, `memory_read`, `memory_search`, `scratchpad`
- Format: pi-memory compatible (MEMORY.md, SCRATCHPAD.md, daily/)
- Context auto-injected on session start (goal + scratchpad + today/yesterday log + MEMORY.md)
- Install `qmd` for semantic/vector search upgrade
- `/goal <text>` — set a pinned session goal (injected as context + shown in the statusline). `/goal` shows it, `/goal clear` clears it.

## Agent Delegation (pi-subagents + custom)

- Use `delegate_agent` tool to spawn sub-agents for parallel or specialized work.
- `check_delegation` to view pueue task status. `wait_delegation` to block until complete.
- Difficulty auto-selects model:
  - `high` → kimi-k2.6:high (design, review, debugging)
  - `medium` → deepseek-v4-pro:high (coding from design)
  - `low` → deepseek-v4-flash:off (summaries, extraction)
- Async mode uses pueue for background execution.
- Sync mode blocks until completion (use for sequential dependencies).
- When delegating, communicate: background, goal, expected output, constraints.

- pi-subagents provides: chain/parallel execution, TUI visualization, built-in agents
- agent-delegation.ts adds: pueue async execution, difficulty-based model auto-selection
- Async sub-agents are pueue tasks labeled `pi-delegate`; the statusline shows their
  running/queued count (`agents r:N q:M`) so background work is visible.

## Workflow Orchestration

Deterministic multi-agent orchestration over headless `pi` sub-agents (`workflow.ts`):

- `agent_parallel` — fan out independent tasks concurrently, collect structured results + total token/cost.
- `agent_pipeline` — push each item through ordered stages ({input} = prev output, {item} = original).
- Sub-agents run as `pi --mode json --no-session`; usage is parsed from the event stream for a real budget (`budgetUSD`).
- `jsonKeys` per task/stage requests + parses JSON output (pi CLI has no schema enforcement; best-effort parse).
- Recursion capped at depth 1 (sub-agents cannot fan out further).

## Session Management

- `/session-name <name>` — set session display name (auto-set from git branch)
- `/sessions` — list recent sessions
- `/session-export [file]` / `/session-import <file>` — export/import JSONL
- `/btw <question>` — quick side question without polluting history

## Remote Control

- pi-remote-control package — `/remote-control-pair` for QR pairing, `/remote-control` to toggle
- Requires iOS app (Pi Relay) + config at `~/.pi/remote-control/config.json`

## Cursor Provider (pi-cursor-agent)

Use Cursor subscription models inside pi's harness via the community `pi-cursor-agent` package
(`settings.json` → `packages`). Tool calls stay in pi (permission-gate, mcp-gateway, etc.);
inference and billing go through Cursor's API.

Setup:

1. `cursor-agent` CLI installed (`install.sh`)
2. In pi: `/login` → **Cursor Agent** → browser OAuth
3. `/model cursor-agent/composer-2-fast` (or any model from `/models`)

Recommended when Cursor quota is the billing target but pi extensions / delegation / skills
are required. Sub-agent delegation (`delegate_agent`) still spawns OpenCode Go / Codex pi instances;
switch the main session model to Cursor when you want Cursor billing on the primary harness.

Caveats: community-maintained (MIT, [sudosubin/pi-frontier](https://github.com/sudosubin/pi-frontier));
unofficial Cursor API surface; token counts may be unavailable from the provider.
