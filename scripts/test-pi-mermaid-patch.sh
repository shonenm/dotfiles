#!/bin/bash
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/pkg"
printf '%s\n' '{"name":"pi-mermaid","version":"0.3.0"}' > "$tmp/pkg/package.json"
printf '%s\n' 'export default function () {}' > "$tmp/pkg/index.ts"

PI_MERMAID_DIR="$tmp/pkg" "$(dirname "$0")/patch-pi-mermaid.sh" >/dev/null
grep -q 'triggerTurn: false' "$tmp/pkg/index.ts"
grep -q 'Do not render on user submit' "$tmp/pkg/index.ts"
echo "pi-mermaid display-only overlay test passed"
