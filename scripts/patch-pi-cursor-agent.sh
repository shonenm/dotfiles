#!/bin/bash
# Overlay local host-thin patches onto the installed pi-cursor-agent package.
set -euo pipefail

pkg_dir="${PI_CURSOR_AGENT_DIR:-$HOME/.pi/agent/npm/node_modules/pi-cursor-agent}"
overlay_root="$(cd "$(dirname "$0")/.." && pwd)/common/pi/.pi/agent/patches/pi-cursor-agent"

if [[ ! -d "$pkg_dir/src" ]]; then
  echo "pi-cursor-agent is not installed at $pkg_dir" >&2
  exit 1
fi

version="$(node -p "require('$pkg_dir/package.json').version")"
overlay="$overlay_root/$version"
if [[ ! -d "$overlay/src" ]]; then
  echo "No overlay for pi-cursor-agent $version (expected $overlay)" >&2
  exit 1
fi

while IFS= read -r -d '' file; do
  rel="${file#"$overlay/"}"
  dest="$pkg_dir/$rel"
  mkdir -p "$(dirname "$dest")"
  cp "$file" "$dest"
  echo "Patched $rel"
done < <(find "$overlay" -type f -print0)

echo "Applied pi-cursor-agent $version host overlay"
