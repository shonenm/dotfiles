#!/usr/bin/env bash
# Smoke test for scripts/statusline-render.sh (Cursor + Claude shaped payloads).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER="$ROOT/scripts/statusline-render.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/statusline-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

run() {
  local host="$1" json="$2" out
  out=$(STATUSLINE_HOST="$host" XDG_STATE_HOME="$TMP/state" XDG_CACHE_HOME="$TMP/cache" \
    bash "$RENDER" <<<"$json" | sed $'s/\033\\[[0-9;]*m//g' | sed $'s/\033\\[[0-9;]*;[0-9;]*m//g')
  # strip remaining OSC/CSI crud for assert
  out=$(printf '%s' "$out" | tr -d '\033' | sed 's/\[[0-9;]*m//g')
  printf '%s' "$out"
}

mkdir -p "$TMP/cache/tmux" "$TMP/state"
printf '42|7|%s\n' "$(( $(date +%s) + 86400 ))" > "$TMP/cache/tmux/cursor_usage"

cursor_json='{
  "session_name": "very long session name that should be truncated eventually for display width reasons",
  "autorun": true,
  "render_width_chars": 120,
  "cwd": "/Users/me/dotfiles",
  "model": {"display_name": "Composer 2", "param_summary": "(Thinking)", "max_mode": true},
  "context_window": {"used_percentage": 81.2},
  "vim": {"mode": "NORMAL"},
  "worktree": {"name": "slot-3"},
  "version": "2026.08.11"
}'

out=$(run cursor "$cursor_json")
printf '%s\n' "$out" | grep -q 'Composer 2 (Thinking) MAX' || fail "model extras missing: $out"
printf '%s\n' "$out" | grep -q 'ctx:.*81%' || fail "ctx missing: $out"
printf '%s\n' "$out" | grep -q 'cursor 42%' || fail "plan usage missing: $out"
printf '%s\n' "$out" | grep -q 'other 7%' || fail "other pool missing: $out"
printf '%s\n' "$out" | grep -q 'auto' || fail "autorun missing: $out"
printf '%s\n' "$out" | grep -q 'wt:slot-3' || fail "worktree missing: $out"
[[ -f "$TMP/state/cursor/statusline-input.json" ]] || fail "cursor state file not written"

# high ctx uses red path — just ensure it still renders at narrow width
narrow=$(STATUSLINE_HOST=cursor XDG_STATE_HOME="$TMP/state" XDG_CACHE_HOME="$TMP/cache" \
  bash "$RENDER" <<<"${cursor_json/120/50}" | tr -d '\033' | sed 's/\[[0-9;]*m//g')
printf '%s\n' "$narrow" | grep -q 'Composer 2' || fail "narrow missing model: $narrow"
printf '%s\n' "$narrow" | grep -qv 'wt:slot-3' || fail "narrow should drop worktree: $narrow"

claude_json='{
  "cwd": "/Users/me/dotfiles",
  "render_width_chars": 120,
  "model": {"display_name": "Opus 5"},
  "context_window": {"used_percentage": 12},
  "cost": {"total_cost_usd": 1.25, "total_duration_ms": 65000, "total_lines_added": 3, "total_lines_removed": 1},
  "version": "2.1.0"
}'
out=$(run claude "$claude_json")
printf '%s\n' "$out" | grep -q 'Opus 5' || fail "claude model: $out"
printf '%s\n' "$out" | grep -q '\$1.2500' || fail "claude cost: $out"
printf '%s\n' "$out" | grep -qv 'cursor ' || fail "claude should not show cursor plan: $out"
[[ -f "$TMP/state/claude/statusline-input.json" ]] || fail "claude state file not written"

echo "statusline-render: OK"
