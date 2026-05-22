---
name: safe-implementation
description: "Make guarded code changes with verification. Prefers small diffs, checks existing code before modifying, runs relevant tests before finishing. Use when implementing features or fixes."
---

# Safe Implementation

Make small, verified changes to code with continuous behavior verification.

## Principles

- **Implement only what is asked** — No speculative changes or future-proofing.
- **Root cause over workarounds** — Investigate before patching symptoms.
- **Small diffs** — One logical change per commit.
- **Verify continuously** — Type check and test after each change.

## Procedure

### 1. Understand the Codebase

Before modifying anything:

```bash
# Read relevant files
cat path/to/file.ts

# Search for related code
rg "related-pattern" --type ts

# Check how the feature is used elsewhere
rg "feature-name" -A 3 -B 3
```

### 2. Plan the Change

Identify:
- Files to modify
- Functions/methods to add/change
- Tests to add/update
- Potential side effects

### 3. Implement

- Make the smallest possible change that achieves the goal.
- Use `edit` for targeted replacements (not full file rewrites).
- Preserve existing code style and patterns.

### 4. Verify

```bash
# Type check (if applicable)
npx tsc --noEmit

# Run relevant tests
npm test -- --grep "related-test"

# Lint
npx eslint path/to/file.ts
```

### 5. Commit

Use `/d-commit` to create logical commits.

## Rules

- **No half-finished work** — Either complete the feature or don't start.
- **No backwards-compatibility shims** unless explicitly requested.
- **No unused code** — Remove dead code you encounter.
- **Update tests** when behavior changes.
- **Ask before scope expansion** — If you believe the scope should grow, confirm with the user.
