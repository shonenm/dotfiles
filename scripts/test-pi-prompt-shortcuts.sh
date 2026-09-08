#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
pi_package=$(dirname "$(dirname "$(realpath "$(command -v pi)")")")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/node_modules/@earendil-works"
ln -s "$pi_package" "$tmp/node_modules/@earendil-works/pi-coding-agent"
ln -s "$pi_package/node_modules/@earendil-works/pi-tui" "$tmp/node_modules/@earendil-works/pi-tui"
cp "$root/common/pi/.pi/agent/extensions/"prompt-{history,stash}.ts "$tmp/"
cd "$tmp"
node --input-type=module - "$root" <<'JS'
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { ExtensionRunner } from "@earendil-works/pi-coding-agent";
const { KeybindingsManager } = await import(new URL("./core/keybindings.js", import.meta.resolve("@earendil-works/pi-coding-agent")).href);
import { setKeybindings, visibleWidth } from "@earendil-works/pi-tui";
import history from "./prompt-history.ts";
import stash from "./prompt-stash.ts";

const keybindings = new KeybindingsManager(JSON.parse(readFileSync(`${process.argv[2]}/common/pi/.pi/agent/keybindings.json`, "utf8")));
setKeybindings(keybindings);
const shortcuts = new Map();
const pi = {
  registerShortcut: (key, shortcut) => shortcuts.set(key, { ...shortcut, extensionPath: "prompt-shortcuts" }),
  registerCommand() {}, on() {},
};
history(pi);
stash(pi);
const runner = new ExtensionRunner([{ shortcuts }], {}, process.cwd(), {}, {});
const available = runner.getShortcuts(keybindings.getResolvedBindings());
assert(available.has("ctrl+s") && available.has("ctrl+r"));
assert.deepEqual(runner.getShortcutDiagnostics(), []);
assert(keybindings.matches("\x1bs", "app.models.save"));
assert(keybindings.matches("\x1bs", "app.session.toggleSort"));
assert(keybindings.matches("\x1br", "app.session.rename"));

const user = (content) => ({ type: "message", message: { role: "user", content } });
let entries = [
  user("first prompt"),
  user([{ type: "text", text: "日本語のテスト\nsecond line" }]),
  { type: "message", message: { role: "assistant", content: [{ type: "text", text: "never searchable" }] } },
  user([{ type: "image", data: "ignored" }]),
  user("latest prompt"), user("latest prompt"),
];
let editor = "unfinished draft";
let exercise;
let notices = [];
const theme = { fg: (_color, text) => text };
const ctx = {
  mode: "tui",
  sessionManager: { getBranch: () => entries },
  ui: {
    theme,
    getEditorText: () => editor,
    setEditorText: (text) => { editor = text; },
    setStatus() {},
    notify: (message) => notices.push(message),
    custom: async (factory) => {
      let result;
      const component = factory({ requestRender() {} }, theme, keybindings, (value) => { result = value; });
      component.focused = true;
      component.invalidate();
      for (const width of [40, 80]) assert(component.render(width).every((line) => visibleWidth(line) <= width));
      exercise(component);
      return result;
    },
  },
};
await available.get("ctrl+s").handler(ctx);
assert.equal(editor, "");
await available.get("ctrl+s").handler(ctx);
assert.equal(editor, "unfinished draft");

exercise = (component) => {
  const text = component.render(80).join("\n");
  assert(!text.includes("never searchable"));
  assert.equal(text.split("latest prompt").length - 1, 1);
  for (const key of "日本語") component.handleInput(key);
  assert(!component.render(80).join("\n").includes("latest prompt"));
  component.handleInput("\r");
};
await available.get("ctrl+r").handler(ctx);
assert.equal(editor, "日本語のテスト\nsecond line");

exercise = (component) => { component.handleInput("\x1b[B"); component.handleInput("\r"); };
await available.get("ctrl+r").handler(ctx);
assert.equal(editor, "日本語のテスト\nsecond line", "Down should select the next distinct prompt");

editor = "keep this draft";
exercise = (component) => {
  for (const key of "no-match-xyz") component.handleInput(key);
  assert(component.render(80).join("\n").includes("No matching prompts"));
  component.handleInput("\r");
  component.handleInput("\x1b");
};
await available.get("ctrl+r").handler(ctx);
assert.equal(editor, "keep this draft");
entries = [];
await available.get("ctrl+r").handler(ctx);
assert(notices.some((message) => message.includes("No prompt history")));
console.log("OK: Ctrl+S stash and Ctrl+R searchable history register without conflicts; restore, cancel, and IME text work");
JS
