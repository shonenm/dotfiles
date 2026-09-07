#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-restore-extras.XXXXXX")"
SOCK="$TMP/tmux.sock"
STATE="$TMP/state"
SNAP="$TMP/snap"

cleanup() {
  tmux -S "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

wrapper="$TMP/tmux-wrap"
cat >"$wrapper" <<EOF
#!/bin/bash
exec "$(command -v tmux)" -S "$SOCK" "\$@"
EOF
chmod +x "$wrapper"

tmux -S "$SOCK" -f /dev/null new-session -d -s extras 'exec sleep 600'
pid=$(tmux -S "$SOCK" display-message -p '#{pid}')
export TMUX="$SOCK,$pid,0"
tmux -S "$SOCK" set-option -t extras @rcon-host example-host
tmux -S "$SOCK" set-option -p @agent_provider pi
tmux -S "$SOCK" set-option -p @agent_transcript_path /tmp/demo.jsonl

TMUX_BIN="$wrapper" TMUX_RESTART_STATE_DIR="$STATE" \
  "$ROOT/scripts/tmux-restore-extras.sh" save "$SNAP"

[[ -f "$SNAP/sessions.tsv" && -f "$SNAP/panes.tsv" && -f "$SNAP/meta.tsv" ]] ||
  fail "snapshot files missing in $SNAP"
[[ -f "$STATE/last/panes.tsv" ]] || fail "last snapshot not published"
grep -q $'example-host' "$SNAP/sessions.tsv" || fail "rcon host not saved"
grep -q $'pi' "$SNAP/panes.tsv" || fail "agent provider not saved"
grep -q $'/tmp/demo.jsonl' "$SNAP/panes.tsv" || fail "transcript path not saved"
grep -q $'attach_session\textras' "$SNAP/meta.tsv" || fail "meta attach_session"

TMUX_BIN="$wrapper" TMUX_RESTART_STATE_DIR="$STATE" \
  "$ROOT/scripts/tmux-restore-extras.sh" restore "$SNAP"
[[ "$(tmux -S "$SOCK" show-options -gv @restore-extras-done)" == 1 ]] ||
  fail "restore flag not set"

out="$(TMUX_BIN="$wrapper" TMUX_RESTART_STATE_DIR="$STATE" \
  "$ROOT/scripts/tmux-restore-extras.sh" restore "$SNAP")"
[[ "$out" == *'already applied'* ]] || fail "expected skip, got: $out"

TMUX_BIN="$wrapper" TMUX_RESTART_STATE_DIR="$STATE" \
  "$ROOT/scripts/tmux-restore-extras.sh" restore "$SNAP" --force >/dev/null

missing_out="$(TMUX_BIN="$wrapper" TMUX_RESTART_STATE_DIR="$STATE" \
  "$ROOT/scripts/tmux-restore-extras.sh" restore "$TMP/missing" 2>&1 || true)"
[[ "$missing_out" == *'no snapshot'* ]] || fail "expected missing snapshot warning: $missing_out"

echo "test-tmux-restore-extras: OK"
