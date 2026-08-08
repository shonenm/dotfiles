---
name: deep-research
description: "Conduct thorough web research using the host agent's native search and fetch tools. Search → fetch → cross-reference → cite. Use when investigating topics, errors, or multiple sources."
---

# Deep Web Research

Conduct thorough, multi-source web investigations with the current runtime's native tools.

## Toolchain Protocol

- **Pi:** `web_search` → `web_cache_lookup` → `web_fetch` → `web_cache_write` → `web_citation_add`.
- **Codex:** use native web search, open the primary sources it finds, and return their URLs.
- If Pi `web_search` is unavailable, delegate only the search to Codex with:

```sh
codex --search exec --skip-git-repo-check --ephemeral \
  -c model_reasoning_effort=medium \
  "Search for <topic>. Return primary-source URLs and exact supporting quotes."
```

Fetch and verify the returned sources in the parent session when possible.

## Rules

1. **Search is for discovery only** — Never rely on search snippets as your answer. Always fetch the full source content.
2. **Multiple sources** — Search with at least 2 different query variations. Cross-reference findings.
3. **Primary sources first** — Official docs > source code > reputable blogs > forums > social media.
4. **Cache when available** — In Pi, check `web_cache_lookup` before fetching and store useful content with `web_cache_write`.
5. **Cite everything** — In Pi, use `web_citation_add`; otherwise retain source URLs in the answer.
7. **Note contradictions** — If sources disagree, mark the conflicting one with `relevance: "contradictory"`.
8. **State uncertainty** — If information is unverified, say so explicitly.

## Search Strategy

Use the runtime's native search with these query variations:

```
1. Exact error message (quoted)
2. Topic + "official documentation"
3. Topic + "best practices" OR "how to"
4. Topic + version number (if applicable)
5. site:specific-domain.com + topic (for domain-restricted search)
```

## Output Format

When presenting research results:

```markdown
## Research Summary

<Answer with inline citations like [1], [2]>

## Sources

[List from web_citation_list or the retained source URLs]

## Unresolved / Uncertain

[Any contradictions or gaps identified]
```

## Cache Location

Pi cached content is stored in `~/.pi/research/`; Codex uses its native search storage.
