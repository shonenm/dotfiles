#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
pi_package="$(npm root -g)/@earendil-works/pi-coding-agent"
agent_home="$HOME"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home/.pi/agent/extensions/pi-automode" "$tmp/agent/sessions" "$tmp/project"
cp "$root/common/pi/.pi/agent/hermes-memory-config.json" "$tmp/agent/"
cp "$root/common/pi/.pi/agent/extensions/pi-automode/config.json" "$tmp/home/.pi/agent/extensions/pi-automode/"
HOME="$tmp/home" PI_CODING_AGENT_DIR="$tmp/agent" PI_VCC_CONFIG_PATH="$tmp/vcc.json" PI_AUTOMODE_SETTINGS_JSON="" \
node --input-type=module - "$root" "$pi_package" "$agent_home" "$tmp" <<'JS'
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
const [root, piPackage, agentHome, tmp] = process.argv.slice(2);
const host = (path) => import(pathToFileURL(join(piPackage, path)).href);
const { loadExtensions } = await host("dist/core/extensions/loader.js");
const { SessionManager } = await host("dist/core/session-manager.js");
const { ExtensionRunner } = await host("dist/core/extensions/runner.js");
const { KeybindingsManager } = await host("dist/core/keybindings.js");
const { DefaultResourceLoader } = await host("dist/core/resource-loader.js");
const { builtInExtensions } = await host("dist/extensions/index.js");
const { getModels } = await host("node_modules/@earendil-works/pi-ai/dist/compat.js");
const memoryRoot = join(agentHome, ".pi/agent/git/github.com/chandra447/pi-hermes-memory");
const agentRoot = join(agentHome, ".pi/agent/git/github.com/meirm/pi-agent-extensions");
const extRoot = join(agentHome, ".pi/agent/git/github.com/tomsej/pi-ext");
const automodeRoot = join(agentHome, ".pi/agent/git/github.com/czottmann/pi-automode");
for (const packageRoot of [memoryRoot, agentRoot, automodeRoot]) {
  const manifest = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8"));
  assert(!Object.keys(manifest.dependencies ?? {}).some((name) => /^(?:@(?:earendil-works|mariozechner)\/pi-|typebox$|@sinclair\/typebox$)/.test(name)));
}
const cwd = join(tmp, "project");
process.chdir(cwd);
const timestamp = new Date().toISOString();
const sessionFile = join(tmp, "agent/sessions/fixture.jsonl");
writeFileSync(sessionFile, [
  { type: "session", version: 3, id: "fixture-session", timestamp, cwd },
  { type: "message", id: "message-1", parentId: null, timestamp, message: { role: "user", content: "purple penguin session fixture" } },
  { type: "message", id: "message-2", parentId: "message-1", timestamp, message: { role: "assistant", content: [{ type: "text", text: "confirmed purple penguin fixture" }], api: "openai-responses", provider: "fixture", model: "fixture", timestamp: Date.now(), stopReason: "stop", usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } } } },
].map((entry) => JSON.stringify(entry)).join("\n") + "\n");
writeFileSync(join(cwd, "fixture.ts"), "export function fixtureAnswer(value: number): number { return value + 1; }\n");
const probe = join(tmp, "host-alias-probe.ts");
writeFileSync(probe, `
import { Type as oldType } from "@sinclair/typebox";
import { Type } from "typebox";
import { Text as oldText } from "@mariozechner/pi-tui";
import { Text } from "@earendil-works/pi-tui";
import { getAgentDir as oldSdk } from "@mariozechner/pi-coding-agent";
import { getAgentDir } from "@earendil-works/pi-coding-agent";
export default function(pi) {
  pi.registerTool({ name: "host_alias_probe", label: "Probe", description: "Host identity probe", parameters: Type.Object({}),
    async execute() { return { content: [], details: { typebox: oldType === Type, tui: oldText === Text, sdk: oldSdk === getAgentDir } }; } });
}
`);
const loaded = await loadExtensions([
  join(memoryRoot, "src/index.ts"),
  ...["ask-user", "todos", "control"].map((name) => join(agentRoot, `extensions/${name}/index.ts`)),
  join(extRoot, "extensions/pi-sem/index.ts"),
  join(extRoot, "extensions/pi-vcc/index.ts"),
  join(automodeRoot, "extensions/auto-mode.ts"),
  probe,
], cwd);
assert.deepEqual(loaded.errors, []);
const tools = new Map(loaded.extensions.flatMap((extension) => [...extension.tools].map(([name, tool]) => [name, tool.definition])));
const notices = [];
const ctx = {
  cwd, mode: "print", hasUI: false,
  sessionManager: SessionManager.open(sessionFile),
  ui: { notify: (message) => notices.push(message), setStatus() {}, select: async (_title, options) => options[0], input: async () => "fixture answer" },
};
const call = async (name, args, context = ctx) => {
  assert(tools.has(name), `${name} must be registered by Pi 1.x`);
  const result = await tools.get(name).execute("fixture", args, undefined, undefined, context);
  assert(!result.isError, JSON.stringify(result));
  return result;
};
try {
  const automode = loaded.extensions.find((extension) => extension.path === join(automodeRoot, "extensions/auto-mode.ts"));
  assert(automode);
  loaded.runtime.appendEntry = (type, data) => ctx.sessionManager.appendCustomEntry(type, data);
  for (const handler of automode.handlers.get("session_start") ?? []) await handler({ type: "session_start" }, ctx);
  const inspection = await call("automode_inspect", { action: "config" });
  assert.equal(inspection.details.config.enabled, true);
  assert.equal(inspection.details.config.classifierModel, "openai-codex/gpt-6-luna");
  assert.equal(inspection.details.config.classifierReasoningLevel, "low");
  assert.deepEqual(inspection.details.diagnostics, []);
  const luna = getModels("openai-codex").find((model) => model.id === "gpt-6-luna");
  assert(luna, "GPT-6 Luna must be available in the host model catalog");
  const classifierCalls = [];
  let providerFails = false;
  const classifierCtx = { ...ctx, model: { provider: "fixture", id: "session-model" }, modelRegistry: {
    find(provider, id) { assert.equal(provider, luna.provider); assert.equal(id, luna.id); return luna; },
    async getApiKeyAndHeaders() { return { ok: true, apiKey: "fixture" }; },
    streamSimple(model, _context, options) {
      classifierCalls.push({ model, options });
      return { async result() {
        if (providerFails) throw new Error("fixture provider unavailable");
        return { role: "assistant", content: [{ type: "text", text: "0" }], api: model.api, provider: model.provider, model: model.id,
          stopReason: "stop", timestamp: Date.now(), usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } } };
      } };
    },
  } };
  const [guard] = automode.handlers.get("tool_call");
  const action = { type: "tool_call", toolCallId: "fixture", toolName: "bash", input: { command: "printf fixture" } };
  assert.equal(await guard(action, classifierCtx), undefined);
  assert.equal(classifierCalls.length, 1);
  assert.equal(classifierCalls[0].options.reasoning, "low");
  assert.equal(classifierCalls[0].options.cacheRetention, "none", "Codex classifier sockets must not be retained");
  providerFails = true;
  const denied = await guard(action, classifierCtx);
  assert.equal(denied.block, true);
  assert(denied.reason.includes("fixture provider unavailable"));
  assert.equal(classifierCalls.length, 2, "Provider errors must not trigger a different classifier");
  const protectedConfig = await guard({ ...action, toolName: "write", input: { path: join(tmp, "home/.pi/agent/extensions/pi-automode/config.json"), content: "{}" } }, classifierCtx);
  assert.equal(protectedConfig.block, true);
  assert.equal(classifierCalls.length, 2, "Safety-control writes must be blocked without a classifier call");
  const identity = await call("host_alias_probe", {});
  assert.deepEqual(identity.details, { typebox: true, tui: true, sdk: true });
  const memory = await call("memory_add", { target: "memory", content: "purple penguin memory fixture" });
  assert(memory.content.some((part) => /added|saved|stored/i.test(part.text)), JSON.stringify(memory));
  const foundMemory = await call("memory_search", { query: "purple penguin", limit: 2 });
  assert.equal(foundMemory.details.success, true, JSON.stringify(foundMemory));
  assert(foundMemory.details.count > 0);
  const foundSession = await call("session_search", { query: "purple penguin", limit: 2 });
  assert.equal(foundSession.details.success, true, JSON.stringify(foundSession));
  assert(foundSession.details.count > 0);
  const question = { questions: [{ question: "Fixture choice?", options: [{ label: "keep" }, { label: "remove" }] }] };
  const answer = await call("ask_user", question, { ...ctx, mode: "tui", hasUI: true });
  assert.equal(answer.details.answers[0].answer, "keep");
  const pending = await call("ask_user", question);
  assert(pending.content[0].text.includes("Questions pending"));
  const todo = await call("todo", { action: "create", title: "fixture todo", body: "preserve data format" });
  const restoredTodo = await call("todo", { action: "get", id: todo.details.todo.id });
  assert.equal(restoredTodo.details.todo.title, "fixture todo");
  await call("list_sessions", {});
  const recall = await call("vcc_recall", { query: "purple", scope: "all" });
  assert(recall.content[0].text.includes("purple penguin"));
  const entities = await call("sem_entities", { file: join(cwd, "fixture.ts") });
  assert(entities.content[0].text.includes("fixtureAnswer"), JSON.stringify(entities));
  const loader = new DefaultResourceLoader({ cwd, agentDir: join(agentHome, ".pi/agent"), noContextFiles: true, extensionFactories: builtInExtensions });
  await loader.reload();
  const runtime = loader.getExtensions();
  assert.deepEqual(runtime.errors, []);
  const runner = new ExtensionRunner(runtime.extensions, runtime.runtime, cwd, {}, {});
  const keybindings = new KeybindingsManager(JSON.parse(readFileSync(join(root, "common/pi/.pi/agent/keybindings.json"), "utf8")));
  runner.getShortcuts(keybindings.getResolvedBindings());
  assert.deepEqual(runner.getShortcutDiagnostics(), []);
  for (const kind of ["commands", "tools", "shortcuts", "flags"]) {
    const owners = new Map();
    for (const extension of runtime.extensions) for (const name of extension[kind].keys()) {
      assert(!owners.has(name), `${kind}: ${name} conflicts between ${owners.get(name)} and ${extension.path}`);
      owners.set(name, extension.path);
    }
  }
  assert(runtime.extensions.some((extension) => extension.path === "builtin:mcp" && extension.commands.has("mcp")));
  const owner = (name) => runtime.extensions.find((extension) => extension.commands.has(name))?.path;
  for (const name of ["btw", "sessions", "review", "handoff"]) assert.equal(owner(name), join(agentRoot, `extensions/${name}/index.ts`));
  assert(owner("loop")?.includes("/@trevonistrevon/pi-loop/"));
  for (const name of ["session-name", "session-export", "session-import"]) assert(owner(name)?.endsWith("/extensions/session-manager.ts"));
  for (const warning of runtime.warnings ?? []) {
    assert.equal(warning.path, join(extRoot, "package.json"));
    assert(warning.warning.includes("Host-provided extension packages"));
  }
  const runtimeTools = new Set(runtime.extensions.flatMap((extension) => [...extension.tools.keys()]));
  for (const name of ["memory_search", "session_search", "ask_user", "todo", "list_sessions", "sem_entities", "sem_context", "sem_impact", "vcc_recall", "automode_inspect"]) assert(runtimeTools.has(name));
  console.log("OK: Pi 1.x host aliases, memory/session search, ask_user, todo, session control, vcc, sem, GPT-6 Luna automode allow/fail-closed/Codex cacheRetention:none; no command/tool/shortcut/flag conflicts");
} finally {
  for (const handler of loaded.extensions[0].handlers.get("session_shutdown") ?? []) await handler({}, ctx);
}
JS
