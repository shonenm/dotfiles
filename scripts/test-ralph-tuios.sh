#!/usr/bin/env bash
# ralph tools inside TUIOS: tmux calls go to the TUIOS tmux shim, and a
# TUIOS-restored pane resumes the recorded ralph-crew daemon.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-tuios.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
trap 'echo "FAIL: line $LINENO" >&2' ERR

fail() { echo "FAIL: $*" >&2; exit 1; }

# Stubs: tuios records its arguments and pane environment; tmux stands for a
# real tmux server that holds a session only when REAL_HAS=1.
mkdir -p "$TMP/bin"
export LOG="$TMP/calls.log"
cat >"$TMP/bin/tuios" <<'EOF'
#!/usr/bin/env bash
echo "tuios $* | session=${TUIOS_SESSION:-} pane=${TUIOS_PANE_ID:-} tmux=${TMUX:-}" >>"$LOG"
EOF
cat >"$TMP/bin/tmux" <<'EOF'
#!/usr/bin/env bash
echo "realtmux $*" >>"$LOG"
[[ "${1:-}" != has-session || "${REAL_HAS:-0}" == 1 ]]
EOF
chmod +x "$TMP/bin/tuios" "$TMP/bin/tmux"
export PATH="$TMP/bin:$PATH"

# --- Detection ---
in_tuios() { bash -c 'source "$1/scripts/ralph-lib.sh"; ralph_in_tuios' _ "$ROOT"; }
TUIOS_SESSION=work TMUX='' in_tuios || fail "a TUIOS pane is not detected"
TUIOS_SESSION=work TMUX=/tmp/tuios-501/tmux/socket,1,0 in_tuios || fail "a pane the TUIOS shim made is not detected"
! TUIOS_SESSION=work TMUX=/private/tmp/tmux-501/default,1,0 in_tuios || fail "tmux inside TUIOS was taken for TUIOS"
! TUIOS_SESSION='' TMUX='' in_tuios || fail "a plain shell was taken for TUIOS"

# --- ralph-crew teardown picks the server that holds the crew session ---
mkdir -p "$TMP/proj/.claude"
printf '{"tmux_session":"crew-x","state_dir":"%s","workers":[],"tasks":[]}\n' "$TMP/state" >"$TMP/proj/.claude/crew.json"
teardown() {
  : >"$LOG"
  (cd "$TMP/proj" && TUIOS_SESSION=work TUIOS_PANE_ID=p1 TMUX='' REAL_HAS="$1" \
    "$ROOT/scripts/ralph-crew" teardown --config .claude/crew.json >"$TMP/out" 2>&1) ||
    fail "teardown failed ($?): $(cat "$TMP/out")"
}
teardown 0
grep -qx 'tuios tmux has-session -t crew-x | session= pane= tmux=' "$LOG" ||
  fail "the shim call kept the pane's session scope: $(cat "$LOG")"
grep -qx 'tuios kill-session crew-x | session=work pane=p1 tmux=' "$LOG" ||
  fail "kill-session did not go to tuios: $(cat "$LOG")"
teardown 1
grep -qx 'realtmux kill-session -t crew-x' "$LOG" ||
  fail "a crew session on the real tmux server was not kept there: $(cat "$LOG")"
! grep -q '^tuios' "$LOG" || fail "tuios was used although real tmux holds the session"

# --- tmux-default-shell resumes the daemon in a restored pane ---
state="$TMP/xdg-state"
mkdir -p "$state/ralph-crew/tuios-resume"
printf 'echo resumed-%s; exit 0\n' "\$TUIOS_PANE_ID" >"$state/ralph-crew/tuios-resume/pane-1"
out="$(HOME="$TMP" XDG_STATE_HOME="$state" TUIOS_RESTORED=1 TUIOS_PANE_ID=pane-1 \
  "$ROOT/scripts/tmux-default-shell" </dev/null 2>/dev/null)"
[[ "$out" == *resumed-pane-1* ]] || fail "restored pane did not resume: $out"
out="$(HOME="$TMP" XDG_STATE_HOME="$state" TUIOS_PANE_ID=pane-1 \
  "$ROOT/scripts/tmux-default-shell" -c 'echo plain' 2>/dev/null)"
[[ "$out" == plain ]] || fail "a pane that was not restored ran the resume command: $out"

echo "test-ralph-tuios: OK"
