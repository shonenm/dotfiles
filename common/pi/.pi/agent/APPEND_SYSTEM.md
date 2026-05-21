# Global Context (Appended to System Prompt)

## Communication
- User communication: Japanese (日本語)
- Documentation and code comments: Preserve the existing language; do not translate them.

## Development Workflow
- Before finishing any task: run type checks and relevant tests.
- Prefer small, reviewable diffs.
- When behavior changes, update or add tests.
- Do not edit generated files (dist/, coverage/, .next/, node_modules/) unless regenerating.

## Safety
- Do not run destructive shell commands without explicit user approval.
- Do not read .env*, private keys, credentials, or production dumps.
- Before large refactors, write a plan to TODO.md or docs/agent-plan.md.

## Web Access Fallback
- Pi has no built-in WebSearch/WebFetch. Use Jina AI via bash tool:
  - WebFetch: `curl -fsSL 'https://r.jina.ai/<URL>'`
  - WebSearch: `curl -fsSL 'https://s.jina.ai/<QUERY>'`
- Rate limit: ~20 RPM without JINA_API_KEY. Set JINA_API_KEY for higher limits.

## Background Processes
- Do not start long-running processes (servers, watchers, daemons) directly from CLI; use `pueue` instead.
- Start: `pueue add -- <command>`
- Manage: `pueue status` / `pueue log` / `pueue follow` / `pueue kill`
