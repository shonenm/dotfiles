#!/bin/bash
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/tui.js" <<'JS'
class TUI {
    doRender() {
        if (this.stopped)
            return;
        const width = this.terminal.columns;
        const height = this.terminal.rows;
        this.render(width, height);
    }
}
JS

PI_TUI_DIST_DIR="$tmp" "$(dirname "$0")/patch-pi-tui.sh" >/dev/null
PI_TUI_DIST_DIR="$tmp" "$(dirname "$0")/patch-pi-tui.sh" >/dev/null

count=$(grep -c 'Local patch: tmux focus zoom' "$tmp/tui.js")
[[ "$count" == 1 ]]
grep -q 'if (width < 4 || height < 2)' "$tmp/tui.js"
echo "pi-tui narrow terminal patch test passed"
