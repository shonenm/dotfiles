# Ralph Pattern v2

An autonomous development loop built entirely with Claude Code's official primitives (Skills, Hooks, Agents). No external tools required.

## Overview

Ralph v2 splits the workflow into two independent commands:

- `/ralph-plan` -- Interactive planning session: requirements, acceptance criteria, design, task decomposition. Outputs a state file.
- `/ralph` -- Autonomous implementation loop: reads the state file, executes tasks, verifies ACs. Zero user interaction.
- `/ralph-cancel` -- Emergency stop with state archiving.

### Key Components

- Skills (`.claude/skills/`) -- User-invocable entry points
- Hooks (`settings.json` / skill frontmatter) -- Deterministic backpressure (CLAUDE.md is a "request", Hooks are "enforcement")
- Agents (`.claude/agents/`) + `isolation: worktree` -- Parallel execution isolation
- Manifest (`/tmp/ralph_session_manifest`) -- State file discovery

## Architecture

```
/ralph-plan "Add auth"          /ralph                      /ralph "Fix bug"
  |                               |                           |
  v                               v                           v
[Interactive dialog]            [Read manifest]             [Skip-plan mode]
Phase 0: Context gathering      |                           Generate minimal
Phase 1: Requirements + AC      v                           state file
Phase 2: Design + tasks       [State file exists?]            |
  |                            Yes -> plan mode               v
  v                            No  -> error                [Same loop as plan]
[Generate state file]            |
[Write manifest]                 v
  |                           [Implementation loop]
  v                             |
"Run /ralph to start"         [PreToolUse] Block AskUserQuestion/EnterPlanMode
                                |
                              [PostToolUse] tsc, eslint, prettier, test, ruff
                                |
                              [Stop Hook] Phase-aware, progress tracking
                                |
                              [Verification phase] Run all ACs
                                |
                              RALPH_COMPLETE
```

## Usage

### Plan + Execute (Recommended)

```
/ralph-plan "Add user authentication with OAuth"
# ... interactive dialog to define ACs and tasks ...
/ralph
# ... autonomous loop ...
```

### Skip-plan (Quick Tasks)

```
/ralph "Fix the authentication bug in src/auth.ts"
/ralph "Add unit tests for the utils module" --max-iterations 10
```

| Argument | Default | Description |
|----------|---------|-------------|
| `<prompt>` | (optional) | Task description (skip-plan mode) |
| `--max-iterations N` | 25 | Maximum loop iterations |

### Cancel Loop

```
/ralph-cancel
```

Archives state file to `/tmp/ralph_archive_<timestamp>.json` before cleanup.

### Parallel Execution

```
/ralph-parallel                                    # Use state file task_graph
/ralph-parallel docs/prd.md                        # From PRD file
/ralph-parallel "Add login page, Add signup page"  # Comma-separated
```

Orchestrates up to 4 concurrent `ralph-worker` sub-agents in isolated worktrees.

## State File Schema

```jsonc
{
  "session_id": "<hash>",
  "phase": "implementation",       // "implementation" | "verification"
  "max_iterations": 25,
  "iteration": 0,
  "created_at": "<ISO8601>",
  "acceptance_criteria": [
    {"id": "AC-1", "description": "...", "verified": false, "verification_command": "..."},
    {"id": "AC-T", "description": "All tests pass", "verified": false, "verification_command": "npm test"},
    {"id": "AC-L", "description": "tsc --noEmit clean", "verified": false, "verification_command": "npx tsc --noEmit"}
  ],
  "task_graph": [
    {"id": "T-1", "name": "...", "deps": [], "status": "pending", "completion_condition": "...", "files": ["..."]}
  ],
  "context_report": "<investigation results>",
  "stall_hashes": [],
  "completion_token": "RALPH_COMPLETE",
  "errors": []
}
```

Discovered via manifest: `/tmp/ralph_session_manifest` (contains path to state file).

## How It Works

### SessionStart Hook (`ralph-session-context.sh`)

Global hook registered in `settings.json`. Runs at session start, returns `additionalContext` with:
- Project structure (tree -L 2)
- Git info (branch, recent commits, uncommitted changes)
- package.json summary (scripts, dependencies)
- Supabase info (migrations, table names)
- tsconfig.json settings

### PreToolUse Hook (skill frontmatter inline)

Blocks interactive tools that would break the autonomous loop:

| Matcher | Action | Reason |
|---------|--------|--------|
| `AskUserQuestion` | `exit 2` (deny) | Prevents questions mid-loop |
| `EnterPlanMode` | `exit 2` (deny) | Prevents plan mode entry |

### Stop Hook (`ralph-stop-hook.sh`)

Manifest-based state discovery. Phase-aware blocking. Decision logic (in priority order):

1. `stop_hook_active=true` + no manifest/state file -> `exit 0` (prevents infinite loop)
2. No state file -> `exit 0` (not a Ralph session)
3. Phase not `implementation`/`verification` -> `exit 0` (pass through)
4. Completion token detected in `last_assistant_message` -> cleanup manifest + state -> `exit 0`
5. `iteration >= max_iterations` -> record error -> cleanup -> `exit 0`
6. Stall detection: `git diff --stat | md5` tracked in `stall_hashes` array. 3 consecutive same hash -> record error -> cleanup -> `exit 0`
7. Otherwise -> increment iteration, update state, return `decision: "block"` with progress info (tasks done/total, pending ACs)

### Backpressure Hook (`ralph-backpressure.sh`)

PostToolUse hook triggered after Write/Edit/MultiEdit:

| Extension | Checks | Condition |
|-----------|--------|-----------|
| `.ts`/`.tsx` | `tsc --noEmit`, `eslint --fix`, `prettier --write`, related test execution | `package.json` exists |
| `.py` | `py_compile`, `ruff --fix` | Python available |
| `.sh` | `shellcheck` | shellcheck installed |
| `.sql` | `supabase db lint` | File in `supabase/migrations/` |
| `.json` | `jq` syntax validation | Always |

Errors returned as `additionalContext`. eslint/prettier auto-fix before reporting. Related test files (`.test.ts`, `.spec.ts`, `__tests__/`) executed automatically.

### Worker Agent (`ralph-worker`)

Defined with `isolation: worktree` for parallel task execution. Structured reporting format:

```
Status: DONE / PARTIAL / BLOCKED
Files changed: ...
Tests: ...
Completion condition: ...
Notes: ...
```

## File Structure

```
dotfiles/
+-- common/claude/.claude/
|   +-- hooks/
|   |   +-- ralph-stop-hook.sh         # Stop hook (manifest-based, phase-aware)
|   |   +-- ralph-backpressure.sh      # PostToolUse hook (tsc/eslint/prettier/test/ruff)
|   |   +-- ralph-session-context.sh   # SessionStart hook (project context)
|   +-- skills/
|   |   +-- ralph/SKILL.md             # /ralph autonomous loop
|   |   +-- ralph-plan/SKILL.md        # /ralph-plan interactive planning
|   |   +-- ralph-cancel/SKILL.md      # /ralph-cancel with archive
|   |   +-- ralph-parallel/SKILL.md    # /ralph-parallel orchestrator
|   +-- agents/
|       +-- ralph-worker/ralph-worker.md  # Worktree-isolated worker
+-- templates/
|   +-- claude-skills/
|   |   +-- ralph/SKILL.md
|   |   +-- ralph-plan/SKILL.md
|   |   +-- ralph-cancel/SKILL.md
|   |   +-- ralph-parallel/SKILL.md
|   +-- claude-agents/
|       +-- ralph-worker/ralph-worker.md
+-- docs/
    +-- ralph.md                       # This documentation
```

`~/.claude/settings.json` contains the SessionStart hook registration.

## Dependencies

- `jq` -- JSON processing in hook scripts (required, fail-open if missing)
- `git` -- Progress detection via `git diff --stat`
- `md5` (macOS) / `md5sum` (Linux) -- Diff hash comparison
- Optional: `shellcheck`, `tsc`, `eslint`, `prettier`, `python`, `ruff`, `supabase` for backpressure checks

## Design Decisions

- Plan/execute split: `/ralph-plan` is interactive, `/ralph` is autonomous. Completely independent commands
- Skip-plan mode: `/ralph "task"` auto-generates minimal state file for backward compatibility
- Manifest-based discovery: `/tmp/ralph_session_manifest` decouples state file naming from session ID
- Phase-aware Stop hook: only blocks during `implementation`/`verification` phases
- Stall detection via `stall_hashes` array in state file (replaces simple counter)
- Error recording in state file `errors` array before cleanup
- State archiving on cancel: `/tmp/ralph_archive_<timestamp>.json` for post-mortem analysis
- Atomic state updates: `jq > tmp && mv tmp state_file` pattern
- Fail-open hooks: `jq` missing -> `exit 0` (don't break non-Ralph sessions)
- Hooks in skill frontmatter: active only during skill execution, no global side effects
- Zero interaction via PreToolUse hook: `AskUserQuestion`/`EnterPlanMode` denied at hook level
- Backpressure auto-fix: eslint/prettier/ruff fix before reporting remaining errors
- Parallel execution max 4 workers: resource constraint
- SessionStart context hook: global in `settings.json`, provides project awareness to all sessions

## Hook Timeouts

| Hook | Timeout |
|------|---------|
| Backpressure (PostToolUse) | 15s |
| Stop (shell) | 15s |
| Session Context (SessionStart) | 10s |

## Verification

1. `stow -d common -t ~ claude` to create symlinks
2. Planning: `/ralph-plan "Create a hello world script"` -- verify 3-phase dialog and state file generation
3. Plan execution: `/ralph` -- verify state file loading and task-by-task execution
4. Skip-plan: `/ralph "Create a hello world script" --max-iterations 3` -- verify auto state file generation
5. Backpressure: Write TypeScript with type errors, verify PostToolUse returns errors + auto-fixes
6. Stall detection: Intentionally stall, verify loop stops after 3 consecutive no-progress
7. Cancel: `/ralph-cancel` -- verify archive creation and cleanup
8. Parallel: `/ralph-parallel` -- verify up to 4 workers in separate worktrees
9. Session context: New session, verify project info in additionalContext
10. Linux: verify jq + git only dependencies
