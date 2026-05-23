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
    - Generally not recommended. Use for summarizing or extracting data that is too voluminous to handle in a main session with high/medium models.
- When calling an agent, clearly communicate the background, goal, expected output, and what not to do.

## Long-running Tasks and Development Servers

- Do not start long-running processes such as development servers, watchers, or daemons directly from the CLI; use **`pueue`** instead.
- Start them with `pueue add -- <command>`, and use `pueue status` / `pueue log` / `pueue follow` / `pueue kill` / `pueue remove` to check status or manage them.
- For parallel agent delegation, queue tasks via pueue:
  ```bash
  pueue add -i --print-task-id -- "pi ... -p '<instruction>' < /dev/null"
  ```
  ```bash
  pueue status
  pueue wait <task-id> # blocks when there is no other parallel work
  pueue log <task-id> # check results/status
  ```

## Web Research

- Use the pi web research toolchain, not raw curl or browser.
- Follow the protocol: **search → fetch → cache → cite → answer**.
- **Search is for discovery only** — Never rely on snippets alone. Always fetch source content.
- **Primary sources first** — Official docs > source code > release notes > blogs > forums.
- **Check cache before fetching** — Use `web_cache_lookup` to avoid redundant requests.
- **Cache everything useful** — Store fetched content with `web_cache_write`.
- **Cite all sources** — Use `web_citation_add` for every source that informed your answer.
- **Never rely on snippets alone** — Fetch full page content before drawing conclusions.
- **Note contradictions** — If sources disagree, mark conflicting ones and state uncertainty.
- **Research results are stored** in `~/.pi/research/`.

## Security

- **Never send secrets to external web tools** — This includes `.env` files, API keys, private keys, tokens, customer data, internal URLs, auth cookies, and private source file full text.
- **Three-tier web permission**:
  - `allow`: Public package names, public error messages, public docs queries.
  - `ask`: Stack traces, file paths, repository-specific questions.
  - `deny`: Secrets, credentials, private source full text.
- **Summarize private errors before searching** — Remove file paths, credentials, and internal context before sending to web tools.
- **Ask before destructive commands** — Block `rm -rf`, `sudo`, `DROP`, `DELETE FROM`, and external network calls involving repo content.

## Development

- Prefer small diffs.
- Check installed package versions before using latest docs.
- Run relevant type checks and tests before finishing any task.
- Update tests when behavior changes.
- Do not leave unused code or backwards-compatibility shims behind.

## Prompts
- Global prompt templates: `/review`, `/plan`, `/implement`, `/commit`

## Skills
- Global skills: `quality-assure`, `safe-refactor`, `dependency-research`, `pr-review`, `incident-debug`, `deep-research`, `docs-research`, `github-research`
- Invoke via `/skill:<name>` or let the agent load them automatically.
- Claude Code skills under `~/.claude/skills/` are also available.

## Extensions
- `permission-gate`: blocks dangerous bash commands pending user confirmation.
- `protected-paths`: blocks writes to secrets, generated files, and dependencies.
- `web-router`: routes search queries through SearXNG → DuckDuckGo → Jina fallback chain.
- `web-fetch`: fetches URL content with Jina → Playwright → Raw fallback chain.
- `web-cache`: local file-based cache for research results under `~/.pi/research/`.
- `citation-store`: tracks research sources and citations.
- `secret-guard`: blocks transmission of secrets, credentials, and sensitive data to external web tools.
- `audit-log`: logs all web tool usage for transparency.
- `statusline`: colorful footer with token stats, context capacity, git branch, and research activity.
