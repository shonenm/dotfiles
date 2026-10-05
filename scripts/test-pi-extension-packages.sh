#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
pi_package="$(npm root -g)/@earendil-works/pi-coding-agent"
agent_home="$HOME"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/agent/extensions" "$tmp/agent/sessions" "$tmp/project"
cp "$root/common/pi/.pi/agent/extensions/pi-better-openai.json" "$tmp/agent/extensions/"
cp "$root/common/pi/.pi/agent/hermes-memory-config.json" "$tmp/agent/"
HOME="$tmp/home" PI_CODING_AGENT_DIR="$tmp/agent" PI_VCC_CONFIG_PATH="$tmp/vcc.json" \
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
const fastRoot = join(agentHome, ".pi/agent/npm/node_modules/pi-better-openai");
assert.equal(JSON.parse(readFileSync(join(fastRoot, "package.json"), "utf8")).version, "0.1.22");
for (const packageRoot of [memoryRoot, agentRoot, fastRoot]) {
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
  join(fastRoot, "index.ts"),
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
  const fast = loaded.extensions.find((extension) => extension.path === join(fastRoot, "index.ts"));
  assert(fast);
  const fastConfigPath = join(tmp, "agent/extensions/pi-better-openai.json");
  const fastConfigBefore = readFileSync(fastConfigPath, "utf8");
  const fastConfig = JSON.parse(fastConfigBefore);
  assert.equal(fastConfig.persistState, false);
  assert.equal(fastConfig.desiredActive, false);
  assert.equal(fastConfig.footer.mode, "status");
  for (const feature of ["usage", "image", "pets"]) assert.equal(fastConfig[feature].enabled, false);
  const settingsPath = join(tmp, "agent/settings.json");
  const settingsBefore = '{"unrelatedSetting":"preserve"}\n';
  writeFileSync(settingsPath, settingsBefore);
  const statuses = new Map();
  const fastCtx = { ...ctx, mode: "tui", hasUI: true,
    model: getModels("openai-codex").find((model) => model.id === "gpt-6.1-sol"),
    modelRegistry: { isUsingOAuth() { assert.fail("Disabled usage must not access authentication"); } },
    ui: { ...ctx.ui, setFooter() { assert.fail("Better OpenAI must not replace the existing footer"); },
      setStatus: (key, value) => statuses.set(key, value) },
  };
  assert(fastCtx.model);
  const emitFast = async (name, event = { type: name }) => {
    const results = [];
    for (const handler of fast.handlers.get(name) ?? []) results.push(await handler(event, fastCtx));
    return results.find((result) => result !== undefined);
  };
  const payload = Object.freeze({ model: fastCtx.model.id, reasoning: { effort: "high" }, input: [] });
  await emitFast("session_start");
  assert.equal(await emitFast("before_provider_request", { payload }), undefined);
  await fast.commands.get("fast").handler("", fastCtx);
  for (const id of ["gpt-6.1-sol", "gpt-6-luna", "gpt-6-sol", "gpt-6-astra", "gpt-5.6-luna"]) {
    fastCtx.model = getModels("openai-codex").find((model) => model.id === id);
    assert(fastCtx.model, `${id} must be in the host catalog`);
    await emitFast("model_select", { model: fastCtx.model });
    const request = Object.freeze({ ...payload, model: id });
    assert.deepEqual(await emitFast("before_provider_request", { payload: request }), { ...request, service_tier: "priority" });
    assert.equal(Object.hasOwn(request, "service_tier"), false);
    assert(statuses.get("better-openai").includes("fast"));
  }
  fastCtx.model = { provider: "cursor-agent", id: "composer-2.5" };
  await emitFast("model_select", { model: fastCtx.model });
  assert.equal(await emitFast("before_provider_request", { payload }), undefined);
  fastCtx.model = getModels("openai-codex").find((model) => model.id === "gpt-6.1-sol");
  await emitFast("model_select", { model: fastCtx.model });
  await fast.commands.get("fast").handler("", fastCtx);
  assert.equal(await emitFast("before_provider_request", { payload }), undefined);
  loaded.runtime.flagValues.set("fast", true);
  await emitFast("session_start");
  assert.equal((await emitFast("before_provider_request", { payload })).service_tier, "priority");
  loaded.runtime.flagValues.set("fast", false);
  await emitFast("session_start");
  assert.equal(await emitFast("before_provider_request", { payload }), undefined);
  await assert.rejects(fast.tools.get("openai_image").definition.execute("fixture", { prompt: "fixture" }, undefined, undefined, fastCtx), /disabled in config/);
  await emitFast("session_shutdown");
  assert.equal(readFileSync(fastConfigPath, "utf8"), fastConfigBefore);
  assert.equal(readFileSync(settingsPath, "utf8"), settingsBefore);
  loaded.runtime.appendEntry = (type, data) => ctx.sessionManager.appendCustomEntry(type, data);
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
  assert.equal(owner("fast"), join(fastRoot, "index.ts"));
  for (const name of ["session-name", "session-export", "session-import"]) assert(owner(name)?.endsWith("/extensions/session-manager.ts"));
  for (const warning of runtime.warnings ?? []) {
    assert.equal(warning.path, join(extRoot, "package.json"));
    assert(warning.warning.includes("Host-provided extension packages"));
  }
  const runtimeTools = new Set(runtime.extensions.flatMap((extension) => [...extension.tools.keys()]));
  for (const name of ["memory_search", "session_search", "ask_user", "todo", "list_sessions", "sem_entities", "sem_context", "sem_impact", "vcc_recall"]) assert(runtimeTools.has(name));
  assert(!runtimeTools.has("automode_inspect"));
  assert.equal(owner("automode"), undefined);
  assert(runtime.extensions.every((extension) => !extension.path.includes("pi-automode")));
  assert(runtime.extensions.some((extension) => extension.path.includes("pi-permission-system")));
  for (const name of ["permission-gate.ts", "protected-paths.ts"]) assert(runtime.extensions.some((extension) => extension.path.endsWith(`/extensions/${name}`)));
  console.log("OK: Pi 1.x host aliases, memory/session search, ask_user, todo, session control, vcc, sem, GPT Fast toggle/CLI flag/initial-off/no config writes/no footer replacement; automode absent, permission guards retained; no command/tool/shortcut/flag conflicts");
} finally {
  for (const handler of loaded.extensions[0].handlers.get("session_shutdown") ?? []) await handler({}, ctx);
}
JS
