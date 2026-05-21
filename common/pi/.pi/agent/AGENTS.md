# AGENTS.md (User Scoped)

## Communication and Language

- User communication: Japanese (日本語)
- Documentation and code comments: Preserve the existing language; do not translate them.

## Skills Guidelines

- AGENTS.md assumes progressive disclosure: it contains only the minimum information needed, while task-specific knowledge and guidelines live elsewhere.
- Select and load the necessary skills as needed for each task.
- Reach for a skill when a task is recurring or has known steps. Invoke via `/skill:<skill-name>` in your prompt or instructions.

## Implementation Principles

- Implement only what is asked. Do not add speculative changes, refactors, or future-proofing.
- If you believe scope should expand, confirm with the user before acting.
- Prefer root-cause fixes over workarounds. Investigate before patching symptoms.
- Do not leave half-finished work, backwards-compatibility shims, or unused code behind.
- Code-style invariants that can be checked statically should be expressed with the environment's linter or ast-grep, not in prompts.

## Coding Style

- Maintain separation of concerns.
- Separate state from logic.
- Prioritize readability and maintainability.
- Follow t-wada-style TDD: implement while continuously verifying behavior with type checking and tests.
- Define contract layers (APIs/types) rigorously using ADTs, and keep implementation layers regenerable.
- Rules that can be checked statically should be expressed with the environment's linter or ast-grep, not in prompts.

## Agent Delegation

- To keep context clean and preserve accuracy, speed, and cost efficiency, proactively delegate yak shaving and work outside the current focus to an appropriate model agent.
  - Good example: When asked to implement something, delegate design, review, or behavior verification to other agents.
  - Bad example: When encountering a deep-rooted error, trying to solve it yourself without launching a debugging agent.
- How to call an agent: `pi --model <provider/model:effort> --fallback-models <provider/model:effort>,... -p '<instructions>'` (left-priority fallback)
  - When a delegated task needs a specific skill, specify it in the prompt: `pi ... -p '/skill:<skill-name> <instructions>'`
- Model selection (assumes OpenCode Go + Codex subscriptions; adjust to whichever providers are authenticated via `/login`):
  - Difficulty: high
    - Option: `--model 'openai-codex/gpt-5.5:high' --fallback-models 'opencode-go/kimi-k2.6:high'`
    - Use for highly abstract problems such as design, difficult deep troubleshooting, or code reviews that require careful reasoning and high confidence.
  - Difficulty: medium
    - Option: `--model 'opencode-go/deepseek-v4-pro:high' --fallback-models 'openai-codex/gpt-5.4:low,openai-codex/gpt-5.3-codex-spark:low'`
    - Use for low-difficulty or low-abstraction tasks, such as coding from an existing design.
  - Difficulty: low
    - Option: `--model 'opencode-go/deepseek-v4-flash:off' --fallback-models 'openai-codex/gpt-5.4-mini:off'`
    - Generic short tasks, mechanical edits, formatting, scaffolding.

## Background Processes

- Do not start long-running processes such as development servers, watchers, or daemons directly from the CLI; use `pueue` instead.
- Start them with `pueue add -- <command>`, and use `pueue status` / `pueue log` / `pueue follow` / `pueue kill` / `pueue remove` to check status or manage them.
- For parallel agent delegation, queue tasks via pueue:
  ```bash
  pueue add -i --print-task-id -- "pi ... -p '<instruction>' < /dev/null"
  ```
  ```bash
  pueue status
  pueue wait <task-id>  # blocks when there is no other parallel work
  pueue log <task-id>   # check results/status
  ```

## Prompts
- Global prompt templates: `/review`, `/plan`, `/implement`, `/commit`

## Skills
- Global skills: `quality-assure`, `safe-refactor`, `dependency-research`, `pr-review`, `incident-debug`
- Invoke via `/skill:<name>` or let the agent load them automatically.
- Claude Code skills under `~/.claude/skills/` are also available.

## Extensions
- `permission-gate`: blocks dangerous bash commands pending user confirmation.
- `protected-paths`: blocks writes to secrets, generated files, and dependencies.
- `web-tools`: adds `web_fetch` and `web_search` custom tools via Jina AI.

## Web Access
- Pi has no built-in WebFetch / WebSearch. Use the `web_fetch`/`web_search` tools, or Jina AI via bash:
  - WebFetch: `curl -fsSL 'https://r.jina.ai/<URL>'` returns markdown.
  - WebSearch: `curl -fsSL 'https://s.jina.ai/<QUERY>'`.
  - Without an API key, both are rate-limited to ~20 RPM. Set `JINA_API_KEY` env var for higher limits.
