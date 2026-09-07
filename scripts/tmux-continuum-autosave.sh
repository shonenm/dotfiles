#!/usr/bin/env bash
# Keep tmux-continuum's save hook in status-right after theme overwrite.
# continuum prepends "#($plugin/scripts/continuum_save.sh)"; themes replace
# status-right and drop it. Re-insert the same interpolation if missing.
set -euo pipefail

tmux_bin="${TMUX_BIN:-tmux}"
command -v "$tmux_bin" >/dev/null 2>&1 || exit 0

manager="${TMUX_PLUGIN_MANAGER_PATH:-${HOME}/.tmux/plugins}"
manager="${manager%/}"
save="${manager}/tmux-continuum/scripts/continuum_save.sh"
[[ -x "$save" ]] || exit 0

interp="#($save)"
current="$("$tmux_bin" show-options -gv status-right 2>/dev/null || true)"
[[ "$current" == *"$interp"* ]] && exit 0
"$tmux_bin" set-option -g status-right "${interp}${current}"
