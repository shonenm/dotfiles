# Codex Global Instructions

## Project context

- Follow the nearest `AGENTS.md`; when absent, `CLAUDE.md` is the configured fallback.
- Shared skills are installed in `~/.codex/skills/`. Read the matching `SKILL.md` before acting.
- Preserve the existing language in documentation and code comments.

## Execution

- Read the existing implementation and trace callers before editing.
- Prefer repository code, the standard library, and native Codex features over new wrappers or dependencies.
- Use native web search and native subagents. Delegate bulky research or long output, but keep repository edits in the parent agent.
- Never expose secrets in commands, logs, output, or commits. Do not read `.env*`, private keys, credentials, or production dumps.
- Stage and commit only explicit paths; never use catch-all `git add` flags or `git commit -a`.
- Run relevant tests and type checks before finishing.
