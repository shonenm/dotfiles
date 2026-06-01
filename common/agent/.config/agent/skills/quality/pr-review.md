---
name: pr-review
description: Review a pull request or branch diff. Use when the user asks for PR feedback before merging.
---

# PR Review

Use this skill when the user asks to review a pull request or branch diff.

## Process
1. Read the PR description and linked issues.
2. Inspect the full diff.
3. Check for: correctness, tests, docs, security, performance, style consistency.
4. Verify that the PR solves the stated problem without scope creep.
5. Identify any missing edge-case handling or error paths.

## Output
- Summary of what the PR does.
- Strengths (what's done well).
- Concerns (bugs, risks, missing tests/docs).
- Suggestions (optional improvements, not blockers).
- Verdict: approve / request changes / comment with guidance.
