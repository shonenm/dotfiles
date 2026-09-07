#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-continuum-autosave.XXXXXX")"
SOCK="$TMP/tmux.sock"

cleanup() {
  tmux -S "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$TMP/plugins/tmux-continuum/scripts"
save="$TMP/plugins/tmux-continuum/scripts/continuum_save.sh"
printf '%s\n' '#!/bin/bash' 'exit 0' >"$save"
chmod +x "$save"

wrapper="$TMP/tmux-wrap"
cat >"$wrapper" <<EOF
#!/bin/bash
exec "$(command -v tmux)" -S "$SOCK" "\$@"
EOF
chmod +x "$wrapper"

tmux -S "$SOCK" -f /dev/null new-session -d -s autosave 'exec sleep 600'
tmux -S "$SOCK" set-option -g status-right 'hello'

TMUX_BIN="$wrapper" TMUX_PLUGIN_MANAGER_PATH="$TMP/plugins" \
  "$ROOT/scripts/tmux-continuum-autosave.sh"

got="$(tmux -S "$SOCK" show-options -gv status-right)"
[[ "$got" == "#($save)hello" ]] || fail "expected interpolation prefix, got: $got"

TMUX_BIN="$wrapper" TMUX_PLUGIN_MANAGER_PATH="$TMP/plugins" \
  "$ROOT/scripts/tmux-continuum-autosave.sh"
got2="$(tmux -S "$SOCK" show-options -gv status-right)"
[[ "$got2" == "$got" ]] || fail "second run duplicated interpolation: $got2"

echo "test-tmux-continuum-autosave: OK"
