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

## Session Management

- `/session-name <name>` — set session display name (auto-set from git branch)
- `/sessions` — list recent sessions
- `/session-export [file]` / `/session-import <file>` — export/import JSONL
- `/btw <question>` — quick side question without polluting history

## Remote Control

- pi-remote-control package — `/remote-control-pair` for QR pairing, `/remote-control` to toggle
- Requires iOS app (Pi Relay) + config at `~/.pi/remote-control/config.json`
