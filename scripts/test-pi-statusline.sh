#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
pi_bin=$(realpath "$(command -v pi)")
pi_package=$(cd "$(dirname "$pi_bin")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home/.pi/research" "$tmp/home/.pi/agent" "$tmp/bin"
ln -s "$pi_package/node_modules" "$tmp/node_modules"
ln -s "$root/common/pi/.pi/agent/extensions/statusline.ts" "$tmp/statusline.ts"
printf '%s' '{"searchCount":3,"fetchCount":5,"cacheHits":2}' >"$tmp/home/.pi/research/stats.json"
printf '%s' '{"demo":{"calls":8,"errors":1}}' >"$tmp/home/.pi/research/mcp-stats.json"
printf '%s' 'Refine the pi statusline' >"$tmp/home/.pi/agent/goal"
printf '%s\n' '#!/bin/sh' \
  'printf '\''%s'\'' '\''{"tasks":{"1":{"label":"pi-delegate","status":"Running"},"2":{"label":"pi-delegate","status":"Queued"}}}'\''' \
  >"$tmp/bin/pueue"
chmod +x "$tmp/bin/pueue"

cd "$tmp"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" node --experimental-strip-types --preserve-symlinks --input-type=module - "$tmp" <<'JS'
import assert from "node:assert/strict";
import { visibleWidth } from "@earendil-works/pi-tui";

const tmp = process.argv[2];
const { default: registerStatusline } = await import(`file://${tmp}/statusline.ts`);
const handlers = new Map();
const commands = new Map();
let footerFactory;
let contextPercent = 42;
let reloaded = false;

registerStatusline({
  registerCommand: (name, options) => commands.set(name, options),
  on(event, handler) {
    const list = handlers.get(event) ?? [];
    list.push(handler);
    handlers.set(event, list);
  },
});

const ctx = {
  sessionManager: {
    getBranch: () => [{
      type: "message",
      message: {
        role: "assistant",
        usage: { input: 12400, output: 3100, cost: { total: 0.38 } },
      },
    }],
  },
  getContextUsage: () => ({ tokens: contextPercent === null ? null : 42000, contextWindow: 100000, percent: contextPercent }),
  model: { id: "gpt-5.6-sol", contextWindow: 100000 },
  ui: {
    setFooter: (factory) => { footerFactory = factory; },
    notify: () => {},
  },
  reload: async () => { reloaded = true; },
};

for (const handler of handlers.get("session_start")) await handler({}, ctx);

const ansi = { success: 32, warning: 33, error: 31, muted: 37, dim: 90 };
const theme = {
  fg: (color, text) => `\x1b[${ansi[color] ?? 36}m${text}\x1b[0m`,
  bg: (_color, text) => text,
};
const footerData = {
  getGitBranch: () => "main",
  getExtensionStatuses: () => new Map([["stash", "📝 STASHED"]]),
  onBranchChange: () => () => {},
};
const component = footerFactory({ requestRender() {} }, theme, footerData);

for (const [width, maxLines] of [[100, 3], [80, 3], [60, 4], [40, 5]]) {
  const lines = component.render(width);
  assert(lines.length <= maxLines, `${width} columns rendered ${lines.length} lines`);
  assert(lines.every((line) => visibleWidth(line) <= width), `${width} column render overflowed`);
  const text = lines.join("\n");
  for (const expected of ["Goal:", "STASHED", "main", "gpt-5.6-sol", "CTX", "TOK", "COST", "AGT", "WEB", "MCP"]) {
    assert(text.includes(expected), `${width} column render omitted ${expected}`);
  }
}

assert(component.render(80).join("\n").includes("\x1b[32m42%\x1b[0m"));
contextPercent = 75;
assert(component.render(80).join("\n").includes("\x1b[33m75%\x1b[0m"));
contextPercent = 90;
assert(component.render(80).join("\n").includes("\x1b[31m90%\x1b[0m"));
contextPercent = null;
assert(component.render(80).join("\n").includes("?"));

await commands.get("statusline").handler("compact", ctx);
const compact = component.render(60);
assert.equal(compact.length, 1);
assert(visibleWidth(compact[0]) <= 60);
assert(compact[0].includes("STASHED"));
assert(compact[0].includes("CTX"));

await commands.get("statusline").handler("off", ctx);
assert.equal(footerFactory, undefined);
await commands.get("statusline").handler("detailed", ctx);
assert(reloaded);

console.log("OK: statusline fits 100/80/60/40 columns and colors context usage thresholds");
JS
