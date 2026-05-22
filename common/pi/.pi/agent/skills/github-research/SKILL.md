---
name: github-research
description: "Research GitHub repositories, issues, PRs, and source code. Clones repos and uses rg/file read instead of reading GitHub HTML pages. Use when investigating open source projects, finding code examples, or debugging library behavior."
---

# GitHub Research

Investigate GitHub repositories, issues, PRs, and source code using a clone-first approach.

## Rules

1. **Never read GitHub HTML pages** — Always clone the repository and use `rg` / `read` to inspect source code.
2. **Issues and PRs are supplementary** — Read them for context, but source code is the primary source of truth.
3. **Use shallow clones** — Only clone what you need to avoid wasting disk space.

## Procedure

### 1. Locate the Repository

Use `web_search_github` to find the repository:

```
web_search_github("topic OR package-name", repo?: "owner/repo")
```

### 2. Clone the Repository

```bash
# Shallow clone (1 commit depth, fast)
git clone --depth 1 https://github.com/<owner>/<repo>.git /tmp/research-<repo>

# If you need release tags
git clone --depth 1 --branch <tag> https://github.com/<owner>/<repo>.git /tmp/research-<repo>

# If you need to search commit history
git clone https://github.com/<owner>/<repo>.git /tmp/research-<repo>
```

### 3. Search Source Code

```bash
cd /tmp/research-<repo>

# Find relevant files
rg -l "search-term" --type-add 'source:*.{ts,js,py,rs,go}' --type source

# Read specific files
cat path/to/file.ts

# Search issues/PRs (if cloned with full history)
git log --oneline --grep="keyword" | head -20
```

### 4. Read Release Notes / Changelog

```bash
# Check for changelog files
find . -iname 'CHANGELOG*' -o -iname 'HISTORY*' -o -iname 'NEWS*' | head -5

# Read GitHub releases (via API)
gh api repos/<owner>/<repo>/releases --jq '.[].tag_name' | head -10
```

### 5. Clean Up

```bash
rm -rf /tmp/research-<repo>
```

## Output Format

```markdown
## <repo> Research

### Findings

<Results from source code analysis>

### Relevant Code

\`\`\`<language>
<source snippet from rg/cat>
\`\`\`

### Related Issues/PRs

<List relevant issues/PRs with links>

## Sources

<Citations>
```
