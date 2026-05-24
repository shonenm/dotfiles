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

## Agent Delegation

- Delegate yak shaving and work outside current focus to a sub-agent.
- `pi --model <provider/model:effort> --fallback-models <...> -p '<instructions>'`
- Model selection:
  - High difficulty: `openai-codex/gpt-5.5:high` / `opencode-go/kimi-k2.6:high`
  - Medium: `opencode-go/deepseek-v4-pro:high` / `openai-codex/gpt-5.4:low`
  - Low: `opencode-go/deepseek-v4-flash:off`

## Long-running Tasks

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
