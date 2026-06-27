#!/usr/bin/env bash
# smug template launcher — fzf-pick a smug config and start it as a tmux session.
# Runs inside `tmux display-popup -E`. Creates the session detached (-d) then
# switches the underlying client to it, avoiding a nested attach in the popup.
set -u

if ! command -v smug >/dev/null 2>&1; then
  echo "smug is not installed (brew install smug / linux.sh)" >&2
  read -rp "Press Enter to close..." _
  exit 1
fi
if ! command -v fzf >/dev/null 2>&1; then
  echo "fzf is required" >&2
  read -rp "Press Enter to close..." _
  exit 1
fi

name="$(
  smug list 2>/dev/null |
    fzf --prompt='smug template> ' \
        --header='enter=start session   esc=cancel'
)" || exit 0
[ -z "$name" ] && exit 0

# If a session named like the config already exists, just switch to it.
if ! tmux has-session -t "=$name" 2>/dev/null; then
  smug start "$name" -d >/dev/null 2>&1
fi
# smug derives the tmux session name from the config's `session:` field; keep it
# equal to the file name so this switch resolves. Falls through harmlessly if not.
tmux switch-client -t "$name" 2>/dev/null || \
  tmux display-message "smug: started '$name' (session name differs from template?)"
