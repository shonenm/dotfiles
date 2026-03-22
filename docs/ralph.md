# Ralph Pattern v2

An autonomous development loop built entirely with Claude Code's official primitives (Skills, Hooks, Agents). No external tools required.

## Overview

Ralph v2 splits the workflow into two independent commands:

- `/ralph-plan` -- Interactive planning session: requirements, acceptance criteria, design, task decomposition. Outputs a state file.
- `/ralph` -- Autonomous implementation loop: reads the state file, executes tasks, verifies ACs. Zero user interaction.
- `/ralph-cancel` -- Emergency stop with state archiving.
- `/ralph-resume` -- Resume from archive: load completed state, add new tasks, regenerate state file.

### Key Components

- Skills (`.claude/skills/`) -- User-invocable entry points
- Hooks (`settings.json` / skill frontmatter) -- Deterministic backpressure (CLAUDE.md is a "request", Hooks are "enforcement")
- Agents (`.claude/agents/`) + `isolation: worktree` -- Parallel execution isolation
- Manifest -- Session-scoped state file discovery (`/tmp/ralph/state/active_<hash>` per session, `/tmp/ralph/state/latest` for cross-session)

## Architecture

```
/ralph-plan "Add auth"          /ralph                      /ralph "Fix bug"
  |                               |                           |
  v                               v                           v
[Interactive dialog]            [Read active/latest]        [Skip-plan mode]
Phase 0: Context gathering      |                           Generate minimal
Phase 1: Requirements + AC      v                           state file
Phase 2: Design + tasks       [State file exists?]            |
  |                            Yes -> plan mode               v
  v                            No  -> error                [Same loop as plan]
[Generate state file]            |
[Write latest_state]             v
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
                              RALPH_COMPLETE + archive state file
                                |
                                v
                     /ralph-resume "Add feature"
                                |
                                v
                     [Load latest archive]
                     [Show completed tasks/ACs]
                     [Define new tasks interactively or from prompt]
                     [Generate new state file with done tasks preserved]
                                |
                                v
                     "Run /ralph to start"
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

### Resume (Continue After Completion)

```
/ralph-resume                              # Interactive: review archive, define new tasks
/ralph-resume "Add error handling"         # Auto-generate tasks from prompt
/ralph-resume "Improve tests" --max-iterations 10
```

Loads the latest archive, preserves completed tasks, adds new tasks, and generates a new state file.

### Cancel Loop

```
/ralph-cancel
```

Archives state file to `/tmp/ralph/state/archive_<timestamp>.json` before cleanup.

### Parallel Execution

```
/ralph-parallel                                    # Use state file task_graph
/ralph-parallel docs/prd.md                        # From PRD file
/ralph-parallel "Add login page, Add signup page"  # Comma-separated
```

Orchestrates up to 4 concurrent workers, each in a separate git worktree + tmux window. Workers are launched via `/ralph` skill (Stop hook autonomous loop + backpressure hook quality gate). The orchestrator handles implementation only: init → gen-prompt → launch → wait → results summary → stop. Merge, cleanup, and PR creation are delegated to separate skills invoked by the user after review.

```
/ralph-collect send T-1 "PRを作成して"             # Send instruction to worker
/ralph-collect save-all                            # Save all worker changes
/ralph-cleanup                                     # Remove worktrees + branches
/ralph-cleanup --keep-results                      # Keep results directory
```

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

Discovery:
- `/tmp/ralph/state/latest` -- Cross-session discovery (written by `/ralph-plan` and `/ralph-resume`, consumed by `/ralph`)
- `/tmp/ralph/state/active_<session_hash>` -- Session-scoped active marker (used by Stop hook and `/ralph-cancel`)

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
| `AskUserQuestion\|EnterPlanMode` | `exit 2` (deny) | Prevents questions mid-loop |

`/ralph-plan` uses `allowed-tools` to exclude Edit/MultiEdit, preventing code modifications during the planning session. Write is permitted only for Phase 3 state file generation (avoids shell escaping issues with jq).

### Stop Hook (`ralph-stop-hook.sh`)

Session-scoped state discovery via `CLAUDE_SESSION_ID`. Phase-aware blocking. Decision logic (in priority order):

1. Compute session hash from `CLAUDE_SESSION_ID`, check `/tmp/ralph/state/active_<hash>`. No active file -> `exit 0` (not a Ralph session)
2. `stop_hook_active=true` + no state file -> `exit 0` (prevents infinite loop)
3. No state file -> `exit 0` (not a Ralph session)
4. Phase not `implementation`/`verification` -> `exit 0` (pass through)
5. Completion token detected in `last_assistant_message` -> cleanup active file + state -> `exit 0`
6. `iteration >= max_iterations` -> record error -> cleanup -> `exit 0`
7. Stall detection: `git diff --stat | md5` tracked in `stall_hashes` array. 3 consecutive same hash -> record error -> cleanup -> `exit 0`
8. Otherwise -> increment iteration, update state, return `decision: "block"` with progress info (tasks done/total, pending ACs)

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

Defined with `isolation: worktree` for use as Task() subagent in sequential `/ralph` runs. Structured reporting format:

```
Status: DONE / PARTIAL / BLOCKED
Files changed: ...
Tests: ...
Completion condition: ...
Notes: ...
```

### Parallel Worker Architecture

`/ralph-parallel` uses a 3-skill phased model with human review between phases:

```
Phase 1: /ralph-parallel (implementation)
  |
  +-- ralph-orchestrate init --force
  +-- ralph-orchestrate gen-prompt-batch task-spec.json
  +-- ralph-orchestrate launch T-1 ... --model sonnet
  |     +-- wt_create ralph/T-1      # git worktree + tmux window via wt-lib.sh
  |     +-- split-window -h          # Left: nvim (review), Right: claude TUI
  |     +-- tmux send-keys "/ralph 'Read prompt.md ...' --skip-plan"
  +-- ralph-orchestrate status --json --wait 20  (loop until all_done)
  +-- ralph-orchestrate results   # Output summary, STOP
  |
  [Human reviews diffs in tmux windows]
  |
Phase 2: /ralph-collect (post-review)
  +-- ralph-orchestrate send T-1 "PRを作成して"
  +-- ralph-orchestrate save-all
  |
Phase 3: /ralph-cleanup
  +-- ralph-orchestrate cleanup-all [--keep-results]
```

Key design choices:
- Workers launched via `/ralph` skill (Stop hook loop + backpressure hook)
- No `--dangerously-skip-permissions` (avoids initial confirmation prompt)
- TUI startup detected via `tmux capture-pane` loop (not `sleep`)
- Completion detected via `RALPH_COMPLETE` in `tmux capture-pane -S -` (full history)
- 3-state worker status: `done` / `dead` (pane gone, no result) / `running`
- No auto-merge. User decides via `/ralph-collect send` or manual merge
- Checkpoint-based resumable orchestration (`checkpoint-read` / `checkpoint`)

### Reviewer Agent (`ralph-reviewer`)

Read-only agent (model: sonnet) that reviews worker changes after parallel execution. Runs `git diff` in each worker worktree and checks code quality, scope compliance, and task completion. Returns APPROVE or REQUEST_CHANGES with issue list.

## File Structure

```
dotfiles/
+-- common/claude/.claude/
|   +-- hooks/
|   |   +-- ralph-stop-hook.sh         # Stop hook (session-scoped, phase-aware)
|   |   +-- ralph-backpressure.sh      # PostToolUse hook (tsc/eslint/prettier/test/ruff)
|   |   +-- ralph-session-context.sh   # SessionStart hook (project context)
|   +-- skills/
|   |   +-- ralph/SKILL.md             # /ralph autonomous loop
|   |   +-- ralph-plan/SKILL.md        # /ralph-plan interactive planning
|   |   +-- ralph-cancel/SKILL.md      # /ralph-cancel with archive
|   |   +-- ralph-resume/SKILL.md     # /ralph-resume from archive
|   |   +-- ralph-parallel/SKILL.md    # /ralph-parallel orchestrator (implementation only)
|   |   +-- ralph-collect/SKILL.md    # /ralph-collect post-review operations
|   |   +-- ralph-cleanup/SKILL.md    # /ralph-cleanup worktree/branch removal
|   +-- agents/
|       +-- ralph-worker/ralph-worker.md    # Worktree-isolated worker (Task subagent)
|       +-- ralph-reviewer/ralph-reviewer.md # Read-only code reviewer (sonnet)
+-- templates/
|   +-- claude-skills/
|   |   +-- ralph/SKILL.md
|   |   +-- ralph-plan/SKILL.md
|   |   +-- ralph-cancel/SKILL.md
|   |   +-- ralph-resume/SKILL.md
|   |   +-- ralph-parallel/SKILL.md
|   +-- claude-agents/
|       +-- ralph-worker/ralph-worker.md
+-- scripts/
|   +-- wt-lib.sh                      # Worktree + tmux window management library
|   +-- ralph-lib.sh                   # Shared utilities (permissions setup)
|   +-- ralph-orchestrate           # Parallel worker lifecycle management
|   +-- ralph-crew                  # Persistent worker management with periodic dispatch
+-- docs/
    +-- ralph.md                       # This documentation
    +-- ralph-crew.md                  # Crew system documentation
```

`~/.claude/settings.json` contains the SessionStart hook registration.

## Dependencies

- `jq` -- JSON processing in hook scripts (required, fail-open if missing)
- `git` -- Progress detection via `git diff --stat`, worktree management
- `tmux` -- Worker window management in parallel mode
- `md5` (macOS) / `md5sum` (Linux) -- Diff hash comparison
- Optional: `shellcheck`, `tsc`, `eslint`, `prettier`, `python`, `ruff`, `supabase` for backpressure checks

## Design Decisions

- Plan/execute split: `/ralph-plan` is interactive, `/ralph` is autonomous. Completely independent commands
- Skip-plan mode: `/ralph "task"` auto-generates minimal state file for backward compatibility
- Session-scoped manifest: `/tmp/ralph/state/active_<hash>` per session prevents cross-session interference. `/tmp/ralph/state/latest` for cross-session discovery (ralph-plan -> ralph handoff)
- Phase-aware Stop hook: only blocks during `implementation`/`verification` phases
- Stall detection via `stall_hashes` array in state file (replaces simple counter)
- Error recording in state file `errors` array before cleanup
- State archiving on all exit paths: completion, max_iterations, stall, and cancel all create `/tmp/ralph/state/archive_<timestamp>.json` for resume and post-mortem analysis
- Atomic state updates: `jq > tmp && mv tmp state_file` pattern
- Fail-open hooks: `jq` missing -> `exit 0` (don't break non-Ralph sessions)
- Hooks in skill frontmatter: loaded globally (known constraint), session-scoped via `CLAUDE_SESSION_ID` in Stop hook
- Zero interaction via PreToolUse hook: `AskUserQuestion`/`EnterPlanMode` denied at hook level
- `/ralph-plan` defense: `allowed-tools` (hide Edit/MultiEdit, Write は Phase 3 状態ファイル生成のみ許可) + prompt reinforcement. PreToolUse hook は skill frontmatter hooks がグローバルに読み込まれる制約により不採用
- Backpressure auto-fix: eslint/prettier/ruff fix before reporting remaining errors
- Parallel execution max 4 workers: resource constraint. Workers launched via `/ralph` skill in tmux panes for observability. No `--dangerously-skip-permissions` (avoids "Are you sure?" confirmation; Stop hook provides autonomous loop instead)
- `wt-lib.sh` extracted from `wt` CLI: shared library for worktree+tmux management, used by both `wt` command and `ralph-orchestrate`
- Parallel results via `/tmp/ralph/results/`: prevents orchestrator context bloat. Orchestrator reads 1-line summaries, not full worker output
- Model mixing: orchestrator uses session model (Opus), workers and reviewer use sonnet
- 3-skill phased parallel model: `/ralph-parallel` (implementation) → human review → `/ralph-collect` (save/send) → `/ralph-cleanup`. Human review is mandatory between implementation and merge
- No auto-merge in parallel mode: user sends PR instructions via `/ralph-collect send` or merges manually
- No auto-commit: ralph does not commit unless task_graph explicitly includes a commit task. ralph-plan/ralph-resume do not generate commit tasks unless the user explicitly requests it
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
9. Resume: `/ralph-resume "Add error handling"` after completion -- verify archive loaded, done tasks preserved, new tasks added
10. Session context: New session, verify project info in additionalContext
11. Linux: verify jq + git only dependencies
