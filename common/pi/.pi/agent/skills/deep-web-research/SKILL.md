---
name: deep-web-research
description: "Conduct thorough web research using the pi web research toolchain. Search → fetch → cross-reference → cite. Use when investigating topics, finding solutions to errors, or gathering information from multiple sources."
---

# Deep Web Research

Conduct thorough, multi-source web investigations using the pi research toolchain.

## Toolchain Protocol

Follow this exact sequence for all research:

```
web_search (discovery)
  ↓
web_fetch / web_fetch_many (source retrieval)
  ↓
web_cache_write (persist findings)
  ↓
web_citation_add (track sources)
  ↓
web_citation_list (summarize with citations)
```

## Rules

1. **Search is for discovery only** — Never rely on search snippets as your answer. Always fetch the full source content.
2. **Multiple sources** — Search with at least 2 different query variations. Cross-reference findings.
3. **Primary sources first** — Official docs > source code > reputable blogs > forums > social media.
4. **Cache everything** — Use `web_cache_write` after fetching useful content. This prevents redundant requests.
5. **Check cache first** — Use `web_cache_lookup` before `web_fetch` to avoid redundant requests.
6. **Cite everything** — Use `web_citation_add` for every source that informed your answer.
7. **Note contradictions** — If sources disagree, mark the conflicting one with `relevance: "contradictory"`.
8. **State uncertainty** — If information is unverified, say so explicitly.

## Search Strategy

Use `web_search` with these query variations:

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

[List from web_citation_list]

## Unresolved / Uncertain

[Any contradictions or gaps identified]
```

## Cache Location

All cached content is stored in `~/.pi/research/`.
