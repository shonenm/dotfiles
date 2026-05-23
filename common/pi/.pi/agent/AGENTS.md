# AGENTS.md (User Scoped)

## Shared Rules

Common rules are in `~/.config/agent/rules/`. These apply to all coding agents:

- `communication.md` — Language and tone
- `implementation.md` — Scope and discipline
- `problem-solving.md` — Debugging and research
- `security.md` — Secret protection and permissions
- `web-research.md` — Search protocol

## Skills Guidelines

- Shared skills are in `~/.config/agent/skills/`.
- Invoke via `/skill:<name>` or let the agent load them automatically.
- Claude Code skills under `~/.claude/skills/` are also available.

## Agent Delegation

- To keep context clean and preserve accuracy, speed, and cost efficiency, proactively delegate yak shaving and work outside the current focus to an appropriate model agent.
- How to call an agent: `pi --model <provider/model:effort> --fallback-models <provider/model:effort>,... -p '<instructions>'` (left-priority fallback)
  - When a delegated task needs a specific skill, specify it in the prompt: `pi ... -p '/skill:<skill-name> <instructions>'`
- Model selection (assumes OpenCode Go + Codex subscriptions):
  - Difficulty: high → `--model 'openai-codex/gpt-5.5:high' --fallback-models 'opencode-go/kimi-k2.6:high'`
  - Difficulty: medium → `--model 'opencode-go/deepseek-v4-pro:high' --fallback-models 'openai-codex/gpt-5.4:low,openai-codex/gpt-5.3-codex-spark:low'`
  - Difficulty: low → `--model 'opencode-go/deepseek-v4-flash:off' --fallback-models 'openai-codex/gpt-5.4-mini:off'`
- When calling an agent, clearly communicate the background, goal, expected output, and what not to do.

## Long-running Tasks and Development Servers

- Do not start long-running processes directly from the CLI; use **`pueue`** instead.
- Start: `pueue add -- <command>`, manage: `pueue status` / `pueue log` / `pueue follow` / `pueue kill`.
- For parallel agent delegation: `pueue add -i --print-task-id -- "pi ... -p '<instruction>' < /dev/null"`

## Development

- Prefer small diffs.
- Run relevant type checks and tests before finishing any task.
- Update tests when behavior changes.
- Do not leave unused code or backwards-compatibility shims behind.

## Extensions

- `permission-gate`: blocks dangerous bash commands pending user confirmation.
- `protected-paths`: blocks writes to secrets, generated files, and dependencies.
- `web-tools`: search, fetch, cache, citation tools (SearXNG + Jina).
- `mcp-gateway`: MCP tool bridge with permission control and audit logging.
- `statusline`: colorful footer with token stats, context capacity, git branch, and research activity.
