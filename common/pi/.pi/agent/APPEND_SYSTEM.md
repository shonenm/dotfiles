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

## Web Access
- Use the `web_search` and `web_fetch` tools (provided by the web-tools extension).
  They cache, cite, and guard against secret/SSRF leakage — prefer them over raw curl.
- Protocol: `web_search` (discovery) → `web_cache_lookup` → `web_fetch` → `web_cache_write` → `web_citation_add`.
- Raw `curl 'https://r.jina.ai/<URL>'` / `curl 'https://s.jina.ai/<QUERY>'` is a last-resort
  fallback only if the tools are unavailable. Rate limit ~20 RPM without JINA_API_KEY.

## Background Processes
- Do not start long-running processes (servers, watchers, daemons) directly from CLI; use `pueue` instead.
- Start: `pueue add -- <command>`
- Manage: `pueue status` / `pueue log` / `pueue follow` / `pueue kill`
