#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
pi_bin=$(realpath "$(command -v pi)")
pi_package=$(cd "$(dirname "$pi_bin")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home/.pi/agent" "$tmp/bin" "$tmp/node_modules/@earendil-works"
ln -s "$pi_package" "$tmp/node_modules/@earendil-works/pi-coding-agent"
ln -s "$pi_package/node_modules/@earendil-works/pi-tui" "$tmp/node_modules/@earendil-works/pi-tui"
cp "$root/common/pi/.pi/agent/extensions/statusline.ts" "$tmp/statusline.ts"
printf '%s' 'detailed' >"$tmp/home/.pi/agent/statusline-mode"
printf '%s\n' '#!/bin/sh' \
  'printf '\''%s'\'' '\''{"tasks":{"1":{"label":"pi-delegate","status":"Running"},"2":{"label":"pi-delegate","status":"Queued"}}}'\''' \
  >"$tmp/bin/pueue"
printf '%s\n' '#!/bin/sh' 'touch "$HOME/ai-usage-called"; exit 1' >"$tmp/bin/ai-usage"
chmod +x "$tmp/bin/pueue" "$tmp/bin/ai-usage"

cd "$tmp"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" node --experimental-transform-types --input-type=module - "$tmp" <<'JS'
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { stripVTControlCharacters } from "node:util";
import { visibleWidth } from "@earendil-works/pi-tui";

const tmp = process.argv[2];
const { default: registerStatusline } = await import(`file://${tmp}/statusline.ts`);
const handlers = new Map();
const commands = new Map();
let footerFactory;
let headerFactory;
let editorFactory = () => ({ render: () => ["border", "draft", "border"] });
let overlay;
let contextPercent = 42;
let branch = "main";
const statuses = new Map([
  ["pi-permission-system", "yolo"],
  ["ponytail", "🐴 ponytail: ⚡ FULL"],
  ["extmgr", "32 pkgs • auto-update off"],
  ["stash", "📝 STASHED"],
  ...Array.from({ length: 6 }, (_, i) => [`notice-${i}`, `notice-${i}`]),
]);
const ansi = { success: 32, warning: 33, error: 31, muted: 37, dim: 90 };
const theme = {
  fg: (color, text) => `\x1b[${ansi[color] ?? 36}m${text}\x1b[0m`,
  bg: (_color, text) => text,
  bold: (text) => text,
};

registerStatusline({
  registerCommand: (name, options) => commands.set(name, options),
  getThinkingLevel: () => "high",
  on(event, handler) {
    const list = handlers.get(event) ?? [];
    list.push(handler);
    handlers.set(event, list);
  },
});

const ctx = {
  hasUI: true,
  cwd: `${tmp}/home/dotfiles`,
  sessionManager: { getBranch: () => assert.fail("Token history must not be collected") },
  getContextUsage: () => ({ tokens: 42000, contextWindow: 100000, percent: contextPercent }),
  model: { provider: "openai-codex", id: "gpt-5.6-sol", contextWindow: 100000 },
  ui: {
    theme,
    setFooter: (factory) => { footerFactory = factory; },
    setHeader: (factory) => { headerFactory = factory; },
    getEditorComponent: () => editorFactory,
    setEditorComponent: (factory) => { editorFactory = factory; },
    setWorkingIndicator: () => {},
    setTitle: () => {},
    setStatus: (key, value) => value === undefined ? statuses.delete(key) : statuses.set(key, value),
    custom: async (factory) => { overlay = factory({}, theme, {}, () => {}); },
    notify: () => {},
  },
};
const emit = async (event, data = {}) => {
  for (const handler of handlers.get(event) ?? []) await handler(data, ctx);
};
const footerData = {
  getGitBranch: () => branch,
  getExtensionStatuses: () => statuses,
  onBranchChange: () => () => {},
};
const footer = () => footerFactory({ requestRender() {} }, theme, footerData);
const text = (lines) => stripVTControlCharacters(lines.join("\n")).replace(/\s+/g, " ");
const compactText = (lines) => text(lines).replace(/\s/g, "");
const removed = /\b(?:CURSOR|yolo|ponytail|FULL|pkgs|auto-update|TOK|TOKENS|COST|WEB|MCP|CTX)\b/i;

await emit("session_start");
await emit("agent_start");
await emit("tool_execution_start", { toolName: "bash" });
const component = footer();
const baseline = compactText(component.render(160));
for (const width of [160, 100, 90, 89, 80, 64, 63, 60, 40]) {
  const lines = component.render(width);
  assert(lines.every((line) => visibleWidth(line) <= width), `${width} column render overflowed`);
  assert.equal(compactText(lines), baseline, `${width} columns changed displayed information`);
  assert(!removed.test(text(lines)), `${width} columns show removed telemetry`);
  for (const expected of ["~/dotfiles", "STASHED", "notice-5", "main", "gpt-5.6-sol", "42%", "bash", "Esc stop", "Enter steer"]) {
    assert(text(lines).includes(expected), `${width} columns omitted ${expected}`);
  }
}
assert.equal(headerFactory({}, theme).render(40).length, 2);
const editorText = text(editorFactory({}, {}, {}).render(80));
assert(editorText.includes("THINK high"));
assert(editorText.includes("42%"));
assert(!editorText.includes("CTX"));

branch = "feature/日本語の長いブランチ名-".repeat(4);
const longBaseline = compactText(component.render(200));
for (const width of [40, 64, 100]) {
  assert.equal(compactText(component.render(width)), longBaseline);
}
for (const width of [0, 1, 2, 10]) {
  assert(component.render(width).every((line) => visibleWidth(line) <= width));
}
branch = "main";

await emit("tool_execution_end");
assert(text(component.render(80)).includes("RUN"));
await emit("agent_settled");
assert(!text(component.render(80)).includes("Esc stop"));
for (const [percent, color] of [[42, 32], [75, 33], [90, 31]]) {
  contextPercent = percent;
  assert(component.render(80).join("\n").includes(`\x1b[${color}m${percent}%\x1b[0m`));
}
contextPercent = null;
assert(text(component.render(80)).includes("?"));

await commands.get("status").handler("", ctx);
overlay.invalidate();
assert(!removed.test(text(overlay.render())));
assert(text(overlay.render()).includes("running 1 · queued 1"));
assert.equal(statuses.get("pi-permission-system"), "yolo", "Hiding badges must not change extension state");
assert(statuses.has("ponytail") && statuses.has("extmgr"));

for (const mode of ["minimal", "compact", "balanced", "detailed", "legacy", "on"]) {
  await commands.get("statusline").handler(mode, ctx);
  assert.equal(compactText(footer().render(40)), compactText(component.render(160)));
}
await commands.get("statusline").handler("off", ctx);
assert.deepEqual(footer().render(80), [], "Off must hide the footer, not restore built-in telemetry");
assert.equal(readFileSync(`${tmp}/home/.pi/agent/statusline-mode`, "utf8"), "off");
await commands.get("statusline").handler("", ctx);
assert(footer().render(80).length > 0);
await emit("turn_end");
assert(!existsSync(`${tmp}/home/ai-usage-called`), "Cursor usage must not be queried");

console.log("OK: statusline preserves information across widths, hides unwanted telemetry, and keeps run controls/context colors");
JS
