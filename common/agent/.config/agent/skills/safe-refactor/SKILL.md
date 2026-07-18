---
name: safe-refactor
description: Rename, extract, move, or clean up code without changing behavior. Use when the user asks for refactoring, deduplication, or structural cleanup.
---

# Safe Refactor

Use this skill when the user asks to rename, extract, move, or clean up code without changing behavior.

## Process
1. Identify the scope of the refactor (files, functions, variables).
2. Ensure there are existing tests covering the target code.
3. If tests are missing, add characterization tests first.
4. Apply the refactor in small, verifiable steps.
5. Run tests after each step.
6. Stop immediately if tests fail and revert the last step.

## Safety Rules
- Never change public API signatures without updating all callers.
- Never delete code that might have side effects unless proven dead.
- Prefer mechanical refactors (rename, extract, inline) over redesign.
- If the refactor grows beyond the original scope, pause and ask the user.
