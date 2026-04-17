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

SAVE_TAG="<save current layout as...>"

while true; do
  CURRENT_SIG="$("$TMUX_LAYOUT" _current-sig 2>/dev/null || echo "?")"

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
        --header='enter=apply/save   ctrl-d=delete   esc=close   * matches current   + save' \
        --delimiter=$'\t' \
        --with-nth=1,2,3 \
        --expect=ctrl-d
  )" || exit 0

  [ -z "$selected" ] && exit 0

  key="$(printf '%s\n' "$selected" | sed -n '1p')"
  row="$(printf '%s\n' "$selected" | sed -n '2p')"
  [ -z "$row" ] && exit 0

  picked_name="$(printf '%s' "$row" | awk -F '\t' '{print $2}')"

  if [ "$key" = "ctrl-d" ]; then
    if [ "$picked_name" = "$SAVE_TAG" ]; then
      continue
    fi
    printf 'delete preset %q? [y/N]: ' "$picked_name"
    read -r answer
    case "${answer:-}" in
      y|Y|yes|YES)
        "$TMUX_LAYOUT" delete "$picked_name" || true
        ;;
    esac
    continue
  fi

  if [ "$picked_name" = "$SAVE_TAG" ]; then
    printf 'preset name (empty to cancel): '
    read -r new_name
    if [ -z "${new_name:-}" ]; then
      continue
    fi
    "$TMUX_LAYOUT" save -f "$new_name"
    exit 0
  fi

  if "$TMUX_LAYOUT" apply "$picked_name"; then
    exit 0
  fi
  echo
  read -rp "Press Enter to close..." _
  exit 1
done
