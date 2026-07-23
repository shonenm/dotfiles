#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
node --input-type=module - "$root" <<'JS'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const root = process.argv[2];
const { default: registerPromptStash } = await import(
  pathToFileURL(`${root}/common/pi/.pi/agent/extensions/prompt-stash.ts`).href
);

const shortcuts = new Map();
const handlers = new Map();
registerPromptStash({
  registerShortcut: (key, options) => shortcuts.set(key, options),
  registerCommand: () => {},
  on: (event, handler) => handlers.set(event, handler),
});

assert(handlers.has("agent_settled"));
assert(!handlers.has("agent_end"));

let editor = "draft";
const statuses = new Map();
const ctx = {
  ui: {
    theme: { fg: (_color, text) => text },
    getEditorText: () => editor,
    setEditorText: (text) => { editor = text; },
    setStatus: (key, value) => value === undefined ? statuses.delete(key) : statuses.set(key, value),
    notify: () => {},
  },
};

await shortcuts.get("ctrl+s").handler(ctx);
assert.equal(editor, "");
assert.equal(statuses.get("stash"), "📝 stashed");

await handlers.get("agent_settled")({}, ctx);
assert.equal(editor, "draft");
assert(!statuses.has("stash"));

editor = "second draft";
await shortcuts.get("ctrl+s").handler(ctx);
editor = "interruption";
await handlers.get("agent_settled")({}, ctx);
assert.equal(editor, "interruption");
assert.equal(statuses.get("stash"), "📝 stashed");

editor = "";
await shortcuts.get("ctrl+s").handler(ctx);
assert.equal(editor, "second draft");
assert(!statuses.has("stash"));

console.log("OK: prompt stash restores only after agent_settled or manual toggle");
JS
