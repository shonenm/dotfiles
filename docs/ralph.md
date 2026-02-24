# Ralph Pattern

An autonomous development loop built entirely with Claude Code's official primitives (Skills, Hooks, Agents). No external tools required.

## Overview

Ralph implements a self-driving development loop where Claude continues working until a completion condition is met. Inspired by the Anthropic 16-agent C compiler case study, the focus is on feedback environment design (test/CI/backpressure) rather than the loop mechanism itself.

### Key Components

- Skills (`.claude/skills/`) -- User-invocable entry points
- Hooks (`settings.json` / skill frontmatter) -- Deterministic backpressure (CLAUDE.md is a "request", Hooks are "enforcement")
- Agents (`.claude/agents/`) + `isolation: worktree` -- Parallel execution isolation

## Architecture

```
/ralph "Build API" --max-iterations 20 --promise "DONE"
  |
  v
[SKILL.md] Create state file + start task
  |
  v
Claude works (Write/Edit)
  |                  |
  v                  v
[PostToolUse Hook]  Claude continues
Type check/lint      |
auto-run, errors     v
fed back via        Claude tries to stop
additionalContext    |
                     v
               [Stop Hook]
                 |
                 +-- No state file -> exit 0 (not a Ralph session)
                 +-- Promise detected -> cleanup -> exit 0
                 +-- Max iterations -> cleanup -> exit 0
                 +-- No progress x3 -> cleanup -> exit 0
                 +-- Incomplete -> block + reason -> Claude continues
```

## Usage

### Single Task Loop

```
/ralph "Create a REST API with CRUD operations" --max-iterations 20 --promise "DONE"
/ralph "Fix the authentication bug in src/auth.ts"
/ralph "Add unit tests for the utils module" --max-iterations 10
```

| Argument | Default | Description |
|----------|---------|-------------|
| `<prompt>` | (required) | Task description |
| `--max-iterations N` | 50 | Maximum loop iterations |
| `--promise TEXT` | RALPH_COMPLETE | Completion promise string |

### Cancel Loop

```
/ralph-cancel
```

Deletes the state file and stops the loop.

### Parallel Execution

```
/ralph-parallel docs/prd.md
/ralph-parallel "Add login page, Add signup page, Add dashboard"
```

Splits tasks and delegates to `ralph-worker` sub-agents running in isolated worktrees.

## How It Works

### Stop Hook (`ralph-stop-hook.sh`)

Executed every time Claude tries to stop. Decision logic (in priority order):

1. `stop_hook_active=true` + no state file -> `exit 0` (prevents infinite loop outside Ralph)
2. No state file -> `exit 0` (not a Ralph session)
3. `last_assistant_message` contains completion promise -> cleanup -> `exit 0`
4. `iteration >= max_iterations` -> cleanup -> `exit 0`
5. No progress detection: compare `git diff --stat | md5` with previous hash. Same 3 times -> cleanup -> `exit 0`
6. Otherwise -> increment iteration, update state, return `decision: "block"` with reason

State file: `/tmp/ralph_<session_id>.json`

### Backpressure Hook (`ralph-backpressure.sh`)

PostToolUse hook triggered after Write/Edit/MultiEdit. Runs type checks and linters automatically:

| Extension | Check Command | Condition |
|-----------|--------------|-----------|
| `.ts`/`.tsx` | `npx tsc --noEmit` | `package.json` exists in project |
| `.py` | `python -m py_compile` | Python available |
| `.sh` | `shellcheck` | shellcheck installed |

Errors are returned as `additionalContext`, making Claude fix them immediately. Unlike CLAUDE.md instructions which can be ignored, hooks execute deterministically.

### Worker Agent (`ralph-worker`)

Defined with `isolation: worktree` for parallel task execution. Each worker operates in an independent git worktree, automatically cleaned up on completion.

## File Structure

```
dotfiles/
+-- common/claude/.claude/
|   +-- hooks/
|   |   +-- ralph-stop-hook.sh         # Stop hook (loop control)
|   |   +-- ralph-backpressure.sh      # PostToolUse hook (type check/lint)
|   +-- skills/
|   |   +-- ralph/SKILL.md             # /ralph main skill
|   |   +-- ralph-cancel/SKILL.md      # /ralph-cancel loop cancellation
|   |   +-- ralph-parallel/SKILL.md    # /ralph-parallel parallel execution
|   +-- agents/
|       +-- ralph-worker/ralph-worker.md  # Worktree-isolated worker agent
+-- templates/
|   +-- claude-skills/
|   |   +-- ralph/SKILL.md
|   |   +-- ralph-cancel/SKILL.md
|   |   +-- ralph-parallel/SKILL.md
|   +-- claude-agents/
|       +-- ralph-worker/ralph-worker.md
+-- docs/
    +-- ralph.md                       # This documentation
```

## Dependencies

- `jq` -- JSON processing in hook scripts
- `git` -- Progress detection via `git diff --stat`
- `md5` (macOS) / `md5sum` (Linux) -- Diff hash comparison
- Optional: `shellcheck`, `tsc`, `python` for backpressure checks

## Design Decisions

- Hooks are defined in skill frontmatter (active only during skill execution, no `settings.json` changes needed)
- `stop_hook_active` checked first: prevents infinite loops when Ralph state file is absent
- Backpressure via PostToolUse hook: deterministic quality gate, not a "please" in CLAUDE.md
- Parallel execution via `isolation: worktree`: leverages official primitive, no manual worktree management
- State files in `/tmp/ralph_<session_id>.json`: session-scoped, auto-cleaned on completion
- Agent Teams (TeammateTool) migration path: `ralph-parallel` can be updated when GA

## Verification

1. `stow -d common -t ~ claude` to create symlinks
2. `claude --debug` for initial test: verify `stop_hook_active` behavior
3. Single loop: `/ralph "Create a hello world script" --max-iterations 3 --promise "RALPH_COMPLETE"`
4. Backpressure: Write TypeScript with type errors, verify PostToolUse hook returns errors
5. No-progress: Intentionally stall task, verify loop stops after 3 consecutive no-progress
6. `/ralph-cancel` to confirm loop cancellation
7. Parallel: `/ralph-parallel` to verify multiple workers in separate worktrees
8. Linux environment: verify with jq + git only dependencies
