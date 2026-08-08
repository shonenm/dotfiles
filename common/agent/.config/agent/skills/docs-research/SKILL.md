---
name: docs-research
description: "Research library, API, framework, or SDK documentation. Always checks installed version first, then looks up official docs, release notes, and changelogs. Use when working with specific libraries or frameworks."
---

# Docs Research

Research documentation for libraries, APIs, frameworks, and SDKs with version awareness.

## Procedure

### 1. Check Installed Version

Always determine what version the user has installed before looking up docs:

```bash
# Node.js packages
npm list <package-name>
# or
node -e "console.log(require('<package-name>/package.json').version)"

# Python packages
pip show <package-name>
pip list | grep -i <package-name>

# System packages
<package> --version
apt list --installed 2>/dev/null | grep <package-name>

# Go modules
go list -m <module-path>
```

### 2. Search for Documentation

Use the runtime's native search with the package name and installed version. In Pi, call `web_search`; in Codex, use native web search. If Pi search is unavailable, follow the Codex fallback in the `deep-research` skill.

Search for:

```
<package-name> <installed-version> documentation
<package-name> <installed-version> changelog OR release notes
```

### 3. Fetch Official Sources

Prioritize in this order:

1. **Official documentation** — docs.{package}.com, package docs URL
2. **GitHub README / docs directory** — find the repo with native search, then `git clone --depth 1` and read locally (see the github-research skill)
3. **Release notes / changelog** — GitHub releases, CHANGELOG.md
4. **API reference** — JSDoc, OpenAPI spec, type definitions

### 4. Cache Findings

In Pi, rely on `web_fetch` auto-caching, use `web_cache_write` only for assembled content, and call `web_citation_add`. In Codex, retain each source URL for the final answer.

### 5. Present Findings

Structure your answer:

```markdown
## <Package> <version> Documentation

### <Topic>

<Explanation with citations>

### Key Changes from Previous Version

<If version upgrade is relevant>

## Sources

<Citations from web_citation_list or retained source URLs>
```

## Rules

- **Never assume latest docs apply to installed version** — Always check first.
- **Official docs > blogs > tutorials** — Primary sources only.
- **Note breaking changes** — Highlight version-specific behavior.
- **Cache aggressively** — Official docs are stable; cache for 30 days.
