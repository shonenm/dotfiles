---
name: code-review
description: "Structured code review with security, quality, and correctness checks. Use when reviewing PRs, commits, or before merging changes."
---

# Code Review

Perform structured code reviews with comprehensive quality checks.

## Procedure

### 1. Gather Context

```bash
# Review a specific branch or commit range
git diff main...HEAD --stat
git diff main...HEAD

# Or review a specific PR
gh pr view <number> --json title,body,filesChanged,additions,deletions
gh pr diff <number>
```

### 2. Review Checklist

Evaluate each change against:

#### Correctness
- [ ] Does the code do what it claims to do?
- [ ] Are there edge cases not handled?
- [ ] Does it break existing functionality?

#### Security
- [ ] Are secrets, keys, or tokens hardcoded?
- [ ] Is user input validated/sanitized?
- [ ] Are file paths protected against traversal?
- [ ] Are SQL/NoSQL queries parameterized?
- [ ] Are permissions/authorization checked?

#### Quality
- [ ] Is the code readable and well-organized?
- [ ] Are there meaningful tests?
- [ ] Are error messages actionable?
- [ ] Is there unnecessary complexity?
- [ ] Are there code smells or duplicated logic?

#### Performance
- [ ] Are there N+1 queries or unnecessary loops?
- [ ] Is memory usage reasonable?
- [ ] Are expensive operations cached?

#### Documentation
- [ ] Are public APIs documented?
- [ ] Are complex algorithms explained?
- [ ] Does the commit message explain "why"?

### 3. Output Format

```markdown
## Code Review

### Summary

<Overall assessment: approve / approve with comments / request changes>

### Issues Found

#### 🔴 Critical (must fix)
- <Security issue or bug>

#### 🟡 Suggestions (consider fixing)
- <Quality or readability improvement>

#### 🔵 Notes (informational)
- <Observation or positive pattern>

### Positive Findings
- <Well-written code, good patterns, etc.>
```

## Rules

- **Be specific** — Reference exact file and line numbers.
- **Explain why** — Don't just say "fix this", explain the risk.
- **Acknowledge good code** — Not everything is a problem.
- **Don't nitpick** — Focus on meaningful issues.
- **Suggest solutions** — When possible, show how to fix.
