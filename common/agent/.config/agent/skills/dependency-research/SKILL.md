---
name: dependency-research
description: Investigate third-party libraries, APIs, or upstream changes. Use when evaluating dependencies, debugging version issues, or researching integration paths.
---

# Dependency Research

Use this skill when investigating third-party libraries, APIs, or upstream changes.

## Process
1. Identify the dependency name, version, and usage site.
2. Check the project's changelog, releases, and migration guides.
3. Search for known issues or breaking changes.
4. Summarize risks, migration effort, and recommended version.
5. If upgrading, outline the upgrade path and test plan.

## Web Access
- Use `web_fetch` or `web_search` tools if available.
- Fallback: `curl -fsSL 'https://r.jina.ai/<URL>'` or `curl -fsSL 'https://s.jina.ai/<QUERY>'`.
