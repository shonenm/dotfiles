# AGENTS.md (User Scoped)

## Infrastructure Spec

The canonical specification for all agent infrastructure components is at:
`docs/specs/agent-infrastructure.md`

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

## Memory

- Persistent across sessions via plain Markdown files in `~/.pi/agent/memory/`
- Tools: `memory_write`, `memory_read`, `memory_search`, `scratchpad`
- Format: pi-memory compatible (MEMORY.md, SCRATCHPAD.md, daily/)
- Context auto-injected on session start (scratchpad + today's log + MEMORY.md)
- Install `qmd` for semantic/vector search upgrade

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

## Session Management

- `/session-name <name>` — set session display name (auto-set from git branch)
- `/sessions` — list recent sessions
- `/session-export [file]` / `/session-import <file>` — export/import JSONL
- `/q <question>` — quick side question without polluting history

## Remote Control

- pi-remote-control package — `/remote-control-pair` for QR pairing, `/remote-control` to toggle
- Requires iOS app (Pi Relay) + config at `~/.pi/remote-control/config.json`
