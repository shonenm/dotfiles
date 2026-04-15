#!/usr/bin/env bash
# tmux-layout menu popup wrapper
# Runs inside `tmux display-popup -E` so stdin/stdout/stderr are the popup's PTY.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_LAYOUT="$SCRIPT_DIR/tmux-layout"
LAYOUT_DIR="${TMUX_LAYOUT_DIR:-$HOME/.config/tmux/layouts}"
mkdir -p "$LAYOUT_DIR"

if ! command -v fzf >/dev/null 2>&1; then
  echo "fzf is required" >&2
  read -rp "Press Enter to close..." _
  exit 1
fi

# Build menu: first line = save action, rest = existing presets
CURRENT_SIG="$("$TMUX_LAYOUT" _current-sig 2>/dev/null || echo "?")"
SAVE_TAG="<save current layout as...>"

lines=()
lines+=("$(printf '+\t%s\t%s' "$SAVE_TAG" "$CURRENT_SIG")")
while IFS=$'\t' read -r name sig; do
  if [ "$sig" = "$CURRENT_SIG" ]; then
    marker="*"
  else
    marker=" "
  fi
  lines+=("$(printf '%s\t%s\t%s' "$marker" "$name" "$sig")")
done < <("$TMUX_LAYOUT" list 2>/dev/null)

selected="$(
  printf '%s\n' "${lines[@]}" |
    fzf \
      --prompt='layout> ' \
      --header='* = matches current topology   + = save current' \
      --delimiter=$'\t' \
      --with-nth=1,2,3
)" || exit 0

[ -z "$selected" ] && exit 0

picked_name="$(printf '%s' "$selected" | awk -F '\t' '{print $2}')"

if [ "$picked_name" = "$SAVE_TAG" ]; then
  # stdin is the popup PTY — plain `read` works
  printf 'preset name: '
  read -r new_name
  if [ -z "${new_name:-}" ]; then
    exit 0
  fi
  "$TMUX_LAYOUT" save -f "$new_name"
  echo
  read -rp "Press Enter to close..." _
  exit 0
fi

if "$TMUX_LAYOUT" apply "$picked_name"; then
  exit 0
fi
# Apply failed — let user read the error
echo
read -rp "Press Enter to close..." _
exit 1
