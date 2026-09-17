#!/bin/bash
# Overlay local display-only patches onto the installed pi-mermaid package.
set -euo pipefail

pkg_dir="${PI_MERMAID_DIR:-$HOME/.pi/agent/npm/node_modules/pi-mermaid}"
overlay_root="$(cd "$(dirname "$0")/.." && pwd)/common/pi/.pi/agent/patches/pi-mermaid"

if [[ ! -f "$pkg_dir/index.ts" ]]; then
  echo "pi-mermaid is not installed at $pkg_dir" >&2
  exit 1
fi

version="$(node -p "require('$pkg_dir/package.json').version")"
overlay="$overlay_root/$version"
if [[ ! -d "$overlay" ]]; then
  echo "No overlay for pi-mermaid $version (expected $overlay)" >&2
  exit 1
fi

while IFS= read -r -d '' file; do
  rel="${file#"$overlay/"}"
  dest="$pkg_dir/$rel"
  mkdir -p "$(dirname "$dest")"
  cp "$file" "$dest"
  echo "Patched $rel"
done < <(find "$overlay" -type f -print0)

echo "Applied pi-mermaid $version host overlay"
