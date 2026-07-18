---
name: quality-assure
description: Review, verify, test, or harden an implementation. Use when the user asks for code review, QA, or confidence checks before merging.
---

# Quality Assure

Use this skill when the user asks to review, verify, test, or harden an implementation.

## Process
1. Inspect the diff and changed files.
2. Identify correctness, security, regression, and maintainability risks.
3. Run targeted tests if available.
4. Suggest minimal fixes before broad refactors.
5. Summarize remaining risks explicitly.

## Output
- Findings ordered by severity (critical / warning / suggestion).
- Exact files and functions when possible.
- Concrete next action.
- Do not rewrite everything; suggest minimal targeted fixes first.
