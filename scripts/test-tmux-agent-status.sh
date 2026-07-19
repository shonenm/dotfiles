#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-agent-test.XXXXXX")"
SOCK_A="$TMP/a.sock"
SOCK_B="$TMP/b.sock"

cleanup() {
  tmux -S "$SOCK_A" kill-server 2>/dev/null || true
  tmux -S "$SOCK_B" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'${3:+ ($3)}"; }

start_server() {
  local socket="$1" session="$2"
  tmux -S "$socket" -f /dev/null new-session -d -s "$session" 'exec sleep 600'
}

use_server() {
  local socket="$1"
  TMUX="$socket,$(tmux -S "$socket" display-message -p '#{pid}'),0"
  export TMUX
  export TMUX_PANE
  TMUX_PANE=$(tmux -S "$socket" display-message -p '#{pane_id}')
}

option() { tmux show-options -pv -t "$TMUX_PANE" "$1" 2>/dev/null || true; }

export XDG_RUNTIME_DIR="$TMP/runtime"
export AGENT_STATUS_DIR="$TMP/status"
mkdir -p "$XDG_RUNTIME_DIR" "$AGENT_STATUS_DIR"
start_server "$SOCK_A" alpha
use_server "$SOCK_A"

PANE="$ROOT/scripts/tmux-claude-pane.sh"
INDEX="$ROOT/scripts/tmux-agent-index.sh"
STATUS="$ROOT/scripts/tmux-agent-status.sh"

"$PANE" start pi event
assert_eq "$(option @agent_status)" running start
assert_eq "$(option @agent_provider)" pi provider
assert_eq "$(option @agent_heartbeat_source)" event source
[[ "$(option @agent_state_since)" =~ ^[0-9]+$ ]] || fail "state_since missing"

"$PANE" set permission pi
assert_eq "$(option @agent_status)" permission permission
"$PANE" heartbeat pi event
assert_eq "$(option @agent_status)" running recovery
"$PANE" set idle pi
"$PANE" heartbeat pi event
assert_eq "$(option @agent_status)" idle stale-heartbeat-must-not-resurrect

"$PANE" start pi event
tmux set-option -p -t "$TMUX_PANE" @agent_heartbeat 1
AGENT_HANG_THRESHOLD=0 "$PANE" hang-scan
assert_eq "$(option @agent_status)" hang event-hang

"$PANE" start fallback screen
tmux set-option -p -t "$TMUX_PANE" @agent_heartbeat 1
tmux set-option -p -t "$TMUX_PANE" @agent_outhash changed-output
AGENT_HANG_THRESHOLD=0 "$PANE" hang-scan
assert_eq "$(option @agent_status)" running screen-change-keeps-running

tmux set-option -p -t "$TMUX_PANE" @agent_heartbeat 1
AGENT_HANG_THRESHOLD=0 "$PANE" hang-scan
assert_eq "$(option @agent_status)" hang screen-first-threshold

"$PANE" start pi event
tmux set-option -p -t "$TMUX_PANE" @agent_heartbeat 1
AGENT_HANG_THRESHOLD=2 "$PANE" hang-scan & scan_pid=$!
"$PANE" heartbeat pi event
wait "$scan_pid"
assert_eq "$(option @agent_status)" running concurrent-heartbeat-wins

# lock待ち時間を古いheartbeat timestampとして保存しないこと。
lock_channel="agent-state-${TMUX_PANE#%}"
tmux wait-for -L "$lock_channel"
"$PANE" heartbeat pi event & heartbeat_pid=$!
sleep 1.1
released=$(date +%s)
tmux wait-for -U "$lock_channel"
wait "$heartbeat_pid"
stored=$(option @agent_heartbeat)
(( stored >= released )) || fail "heartbeat timestamp was sampled before pane lock"

"$INDEX" refresh
"$PANE" set idle pi
cache_line=$("$INDEX" panes | grep -F "$TMUX_PANE")
case "$cache_line" in *$'\x1fidle\x1f'*) ;; *) fail "semantic transition did not invalidate index";; esac

"$PANE" set permission pi
AGENT_INDEX_DIR=/dev/null/not-a-directory "$STATUS" list | grep -q permission || fail "direct tmux fallback failed"
"$STATUS" list | grep -q ' · pi · ' || fail "provider label missing"

# refresh中の古いsnapshotが後からfresh扱いされないこと。
for _ in 1 2 3 4 5; do
  "$PANE" start pi event
  "$INDEX" refresh & refresh_pid=$!
  "$PANE" set idle pi
  wait "$refresh_pid"
  cache_line=$("$INDEX" panes | grep -F "$TMUX_PANE")
  case "$cache_line" in *$'\x1fidle\x1f'*) ;; *) fail "refresh/invalidate race published stale state";; esac
done

"$PANE" clear
cat > "$AGENT_STATUS_DIR/claude-old.json" <<'JSON'
{"updated":10,"status":"idle","workspace":"w","project":"remote:claude","tool":"claude"}
JSON
cat > "$AGENT_STATUS_DIR/gemini-old.json" <<'JSON'
{"updated":10,"status":"idle","workspace":"w","project":"remote:gemini","tool":"gemini"}
JSON
cat > "$AGENT_STATUS_DIR/gemini-new.json" <<'JSON'
{"updated":20,"status":"none","workspace":"w","project":"remote:gemini","tool":"gemini"}
JSON
remote_rows=$("$STATUS" list)
assert_eq "$(printf '%s\n' "$remote_rows" | grep -c '^.*idle')" 1 provider-tombstone
printf '%s\n' "$remote_rows" | grep -q ' · claude · ' || fail "provider-scoped remote record missing"

for key in status heartbeat state_since outhash heartbeat_source provider stashed; do
  assert_eq "$(option "@agent_$key")" "" "clear $key"
done

start_server "$SOCK_B" beta
use_server "$SOCK_A"
"$INDEX" refresh
assert_eq "$("$INDEX" sessions | cut -d$'\x1f' -f1)" alpha alpha-cache
use_server "$SOCK_B"
"$INDEX" refresh
assert_eq "$("$INDEX" sessions | cut -d$'\x1f' -f1)" beta beta-cache
use_server "$SOCK_A"
assert_eq "$("$INDEX" sessions | cut -d$'\x1f' -f1)" alpha alpha-isolated

echo "tmux agent status tests: ok"
