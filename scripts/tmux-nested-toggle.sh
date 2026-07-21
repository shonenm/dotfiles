#!/bin/sh
# Toggle nested tmux mode (F12)
# ON:  disable outer tmux bindings, pass keys through to inner tmux
# OFF: restore outer tmux bindings

case "${1:-toggle}" in
on)
  fg=$(tmux show-option -gqv @theme-fg-subtle)
  bg=$(tmux show-option -gqv @theme-bg-dark)
  fg=${fg:-"#545c7e"}
  bg=${bg:-"#1a1b26"}
  tmux set prefix None \; \
       set key-table off \; \
       set status-style "fg=${fg},bg=${bg}" \; \
       set window-status-current-format "#[fg=${fg},bg=${bg}] #I #W " \; \
       set window-status-current-style "fg=${fg},bg=${bg}"
  if [ "$(tmux display -p "#{pane_in_mode}")" = "1" ]; then
    tmux send-keys -X cancel
  fi
  tmux refresh-client -S
  ;;
off)
  tmux set -u prefix \; \
       set -u key-table \; \
       set -u status-style \; \
       set -u window-status-current-format \; \
       set -u window-status-current-style \; \
       refresh-client -S
  ;;
*)
  echo "Usage: $0 {on|off}" >&2
  exit 1
  ;;
esac
