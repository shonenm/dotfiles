#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
pi_package="$(npm root -g)/@earendil-works/pi-coding-agent"
node --input-type=module - "$root" "$pi_package" <<'JS'
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
const [root, piPackage] = process.argv.slice(2);
const load = (path) => import(pathToFileURL(join(piPackage, path)).href);
const { loadMcpConfig } = await load("dist/extensions/mcp/config.js");
const { loadExtensionFromFactory, createExtensionRuntime } = await load("dist/core/extensions/loader.js");
const { createEventBus } = await load("dist/core/event-bus.js");
const { builtInExtensions } = await load("dist/extensions/index.js");
const { createJiti } = await load("node_modules/jiti/lib/jiti.mjs");
const jiti = createJiti(import.meta.url, {
  alias: { "@earendil-works/pi-coding-agent": join(piPackage, "dist/index.js") },
});
const { PermissionManager } = await jiti.import(join(process.env.HOME, ".pi/agent/npm/node_modules/pi-permission-system/src/permission-manager.ts"));
const agentDir = join(root, "common/pi/.pi/agent");
const settings = JSON.parse(readFileSync(join(agentDir, "settings.json"), "utf8"));
const sources = settings.packages.map((pkg) => typeof pkg === "string" ? pkg : pkg.source);
assert(sources.includes("npm:pi-remote-control@1.0.7"));
assert(!settings.extensions.includes("-builtin:mcp"));
assert(!existsSync(join(agentDir, "extensions/mcp-gateway.ts")));
assert.equal(realpathSync(join(agentDir, "mcp.json")), realpathSync(join(root, "common/agent/.config/agent/mcp.json")));
const tmp = mkdtempSync(join(tmpdir(), "pi-mcp-test-"));
try {
  const global = loadMcpConfig({ agentDir, cwd: tmp, projectTrusted: false });
  assert.deepEqual(global.errors, []);
  const shared = JSON.parse(readFileSync(join(agentDir, "mcp.json"), "utf8"));
  assert.deepEqual(global.servers.map((server) => server.name).sort(), Object.keys(shared.mcpServers).sort());
  const name = global.servers[0].name;
  mkdirSync(join(tmp, ".pi"));
  writeFileSync(join(tmp, ".pi/mcp.json"), JSON.stringify({ mcpServers: { [name]: { command: "project-server" } } }));
  writeFileSync(join(tmp, ".mcp.json"), JSON.stringify({ mcpServers: { legacy: { command: "legacy-server" } } }));
  assert.equal(loadMcpConfig({ agentDir, cwd: tmp, projectTrusted: false }).servers[0].scope, "global");
  const trusted = loadMcpConfig({ agentDir, cwd: tmp, projectTrusted: true });
  assert.equal(trusted.servers.find((server) => server.name === name).config.command, "project-server");
  assert(!trusted.servers.some((server) => server.name === "legacy"));
  const manager = new PermissionManager({
    globalConfigPath: join(agentDir, "pi-permissions.jsonc"), agentsDir: tmp,
    legacyGlobalSettingsPath: join(tmp, "missing.json"), mcpServerNames: [],
  });
  assert.equal(manager.checkPermission("mcp__example__read", {}).state, "ask");
  assert.equal(manager.checkPermission("mcp__example__write", {}).state, "ask");
  assert.equal(manager.checkPermission("read", {}).state, "allow");
  const builtin = builtInExtensions.find((extension) => extension.name === "mcp");
  const extension = await loadExtensionFromFactory(builtin.factory, tmp, createEventBus(), createExtensionRuntime(), "builtin:mcp");
  assert(extension.commands.has("mcp"));
  const fixtureAgent = join(tmp, "agent");
  mkdirSync(fixtureAgent);
  const server = `
    const readline = require('node:readline');
    readline.createInterface({input: process.stdin}).on('line', line => {
      const message = JSON.parse(line);
      if (message.id === undefined) return;
      const result = message.method === 'initialize'
        ? {protocolVersion:'2025-11-25', capabilities:{tools:{}}, serverInfo:{name:'fixture',version:'1'}}
        : message.method === 'tools/list'
          ? {tools:[{name:'echo',description:'fixture tool',inputSchema:{type:'object',properties:{}}}]}
          : {};
      console.log(JSON.stringify({jsonrpc:'2.0',id:message.id,result}));
    });`;
  writeFileSync(join(fixtureAgent, "mcp.json"), JSON.stringify({ mcpServers: { fixture: { command: process.execPath, args: ["-e", server] } } }));
  const output = execFileSync("pi", ["mcp", "list"], { cwd: fixtureAgent, env: { ...process.env, PI_CODING_AGENT_DIR: fixtureAgent }, encoding: "utf8", timeout: 15000 });
  assert(output.includes("fixture") && output.includes("echo"), "standard CLI must connect and list fixture tools");
  console.log("OK: standard MCP config/link, project trust, permissions, /mcp registration, and stdio connection");
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
JS
