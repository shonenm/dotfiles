#!/bin/bash
# pi-tui が tmux の極小 pane (1列/1行) で描画して例外終了するのを防ぐ local patch。
set -euo pipefail

dist_dir="${PI_TUI_DIST_DIR:-$(npm root -g)/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui/dist}"

node - "$dist_dir" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const dir = process.argv[2];
const files = ["tui-main-screen.js", "tui.js"];
const needle = `    doRender() {
        if (this.stopped)
            return;
        const width = this.terminal.columns;
        const height = this.terminal.rows;
`;
const replacement = `${needle}        // Local patch: tmux focus zoom may temporarily reduce a sibling pane to 1 row/column.
        // Suspend rendering until it is visible again; rendering at that size crashes and scrolls the terminal.
        if (width < 4 || height < 2)
            return;
`;
let found = 0;

for (const name of files) {
  const file = path.join(dir, name);
  if (!fs.existsSync(file)) continue;
  const source = fs.readFileSync(file, "utf8");
  if (source.includes("Local patch: tmux focus zoom")) {
    found++;
    continue;
  }
  if (!source.includes(needle)) continue;
  fs.writeFileSync(file, source.replace(needle, replacement));
  found++;
  console.log(`Patched ${file}`);
}

if (found === 0) {
  console.error(`No compatible pi-tui renderer found in ${dir}`);
  process.exit(1);
}
NODE
