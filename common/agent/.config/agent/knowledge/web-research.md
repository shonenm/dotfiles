# Web Research

Use the web research toolchain, not raw curl or browser.

- Follow the protocol: **search → fetch → cache → cite → answer**.
- Search is for discovery only — never rely on snippets alone. Always fetch source content.
- Primary sources first — Official docs > source code > release notes > blogs > forums.
- Check cache before fetching — use `web_cache_lookup` to avoid redundant requests.
- Cache everything useful — store fetched content with `web_cache_write`.
- Cite all sources — use `web_citation_add` for every source that informed your answer.
- Note contradictions — if sources disagree, mark conflicting ones and state uncertainty.
- Research results are stored in `~/.pi/research/`.
