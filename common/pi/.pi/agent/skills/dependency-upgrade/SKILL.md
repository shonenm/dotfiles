---
name: dependency-upgrade
description: "Safe dependency upgrades with changelog analysis and impact assessment. Check installed version, review changelog, assess breaking changes, and upgrade with verification. Use when updating package versions."
---

# Dependency Upgrade

Perform safe dependency upgrades with thorough changelog analysis.

## Procedure

### 1. Check Current Version

```bash
# Node.js
npm list <package>
cat package.json | grep "<package>"

# Python
pip show <package>
cat requirements.txt | grep <package>

# Go
go list -m <module>
cat go.mod | grep <module>
```

### 2. Find Latest Version

```bash
# npm
npm view <package> version
npm outdated <package>

# pip
pip index versions <package>

# GitHub releases
gh api repos/<owner>/<repo>/releases --jq '.[0].tag_name'
```

### 3. Analyze Changelog

Research the changes between current and target version:

```bash
# Fetch release notes
gh api repos/<owner>/<repo>/releases --jq '.[] | select(.tag_name == "<version>") | .body'

# Or fetch CHANGELOG.md via web research
web_search_docs("<package> changelog")
web_fetch("<changelog-url>")

# Compare commits
gh api repos/<owner>/<repo>/compare/<old-version>...<new-version> --jq '.commits[].message' | head -50
```

### 4. Assess Breaking Changes

Look for:
- Major version bumps (SemVer)
- "Breaking Change" or "BREAKING" in changelog
- Removed APIs or deprecated features
- Changed function signatures
- Updated peer dependency requirements
- Changed default behavior

### 5. Perform Upgrade

```bash
# Node.js
npm install <package>@<version>
npm install <package>@latest  # if latest is safe

# Python
pip install "<package>>=<version>"

# Go
go get <module>@<version>
```

### 6. Verify

```bash
# Type check
npx tsc --noEmit

# Run tests
npm test
npm run test:e2e  # if available

# Check for runtime errors
# Start the app and verify critical paths
```

### 7. Output Format

```markdown
## Dependency Upgrade: <package>

| | Current | Target |
|--|---------|--------|
| Version | <old> | <new> |
| Breaking changes | <none / list> | |

### Changes
- <Key change 1>
- <Key change 2>

### Verification
- [ ] Type check passed
- [ ] Tests passed
- [ ] Manual verification (if needed)

### Risks
<If any remaining concerns>
```

## Rules

- **Never skip changelog review** — Always check what changed.
- **Upgrade one package at a time** — Isolate issues.
- **Prefer minor/patch over major** — Major versions need extra scrutiny.
- **Pin exact versions** — Don't use `^` or `~` in production if stability is critical.
- **Update related packages together** — e.g., `@tanstack/react-query` and `@tanstack/query-core`.
