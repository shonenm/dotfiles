#!/usr/bin/env bash
# Thin wrapper — shared implementation lives in scripts/statusline-render.sh.
# Resolves through stow symlinks (relative or absolute) and fails open (empty
# statusline) if the repo layout is absent, never erroring on the every-turn path.
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
_render="$(cd "$(dirname "$_src")/../../.." 2>/dev/null && pwd)/scripts/statusline-render.sh"
[ -x "$_render" ] && exec "$_render"
exit 0
