// MCP Gateway Extension for pi
//
// Provides an audited bridge to MCP (Model Context Protocol) servers.
// Registered MCP tools are authorized solely by pi-permission-system, so its
// policy and session mode apply consistently to interactive and headless runs.
//
// Architecture:
//   LLM → pi tool (mcp_<server>_<tool>)
//       → pi-permission-system (allow/ask/deny)
//       → audit log
//       → MCP stdio client
//       → MCP server process
//
// Config sources (merged, later overrides earlier):
//   1. ~/.config/agent/mcp.json   (global, shared across agents — see AGENTS.md)
//   2. .mcp.json                   (project)
//   3. .pi/mcp.json                (pi overrides)

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { ChildProcess, spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, appendFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { createInterface } from "node:readline";
import { Writable } from "node:stream";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface MCPServerConfig {
  command: string;
  args: string[];
  env?: Record<string, string>;
  description?: string;
  enabled?: boolean;
  /** Maximum result size in characters (default 10000) */
  maxResultSize?: number;
}

interface MCPConfig {
  mcpServers: Record<string, MCPServerConfig>;
}

interface MCPToolDef {
  name: string;
  description?: string;
  inputSchema: {
    type: "object";
    properties?: Record<string, unknown>;
    required?: string[];
  };
}

type JSONRPCRequest = {
  jsonrpc: "2.0";
  id: number;
  method: string;
  params?: Record<string, unknown>;
};

type JSONRPCResponse = {
  jsonrpc: "2.0";
  id: number;
  result?: unknown;
  error?: { code: number; message: string };
};

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const RESEARCH_DIR = join(homedir(), ".pi", "research");
const MCP_AUDIT_FILE = join(RESEARCH_DIR, "mcp-audit.jsonl");
const MCP_STATS_FILE = join(RESEARCH_DIR, "mcp-stats.json");
const DEFAULT_MAX_RESULT = 8000;
// Preferred MCP protocol version we advertise in `initialize`. The actual
// version is negotiated: the server replies with the version it will use, which
// we accept (tools/list and tools/call are stable across these revisions).
const PREFERRED_PROTOCOL_VERSION = "2025-11-25";

function loadConfig(cwd: string): MCPConfig {
  const merged: MCPConfig = { mcpServers: {} };

  // 1. Global: ~/.config/agent/mcp.json (shared location per AGENTS.md / spec)
  const globalPath = join(homedir(), ".config", "agent", "mcp.json");
  if (existsSync(globalPath)) {
    try {
      const g = JSON.parse(readFileSync(globalPath, "utf-8"));
      Object.assign(merged.mcpServers, g.mcpServers ?? {});
    } catch { /* ignore */ }
  }

  // 2. Project: .mcp.json
  const projectPath = join(cwd, ".mcp.json");
  if (existsSync(projectPath)) {
    try {
      const p = JSON.parse(readFileSync(projectPath, "utf-8"));
      Object.assign(merged.mcpServers, p.mcpServers ?? {});
    } catch { /* ignore */ }
  }

  // 3. Pi overrides: .pi/mcp.json
  const piPath = join(cwd, ".pi", "mcp.json");
  if (existsSync(piPath)) {
    try {
      const pi = JSON.parse(readFileSync(piPath, "utf-8"));
      Object.assign(merged.mcpServers, pi.mcpServers ?? {});
    } catch { /* ignore */ }
  }

  return merged;
}

function getEnabledServers(config: MCPConfig): [string, MCPServerConfig][] {
  return Object.entries(config.mcpServers).filter(
    ([, cfg]) => cfg.enabled !== false
  );
}

// ---------------------------------------------------------------------------
// MCP Client (minimal JSON-RPC over stdio)
// ---------------------------------------------------------------------------

class MCPClient {
  private proc: ChildProcess | null = null;
  private reqId = 0;
  private pending = new Map<number, (res: JSONRPCResponse) => void>();
  private buffer = "";
  private initialized = false;
  private negotiatedVersion = "";
  private serverName: string;

  constructor(private config: MCPServerConfig, name: string) {
    this.serverName = name;
  }

  async start(): Promise<void> {
    if (this.proc) return;

    const env = { ...process.env, ...(this.config.env ?? {}) };

    return new Promise((resolve, reject) => {
      const cmd = this.config.command;
      const args = this.config.args;

      this.proc = spawn(cmd, args, {
        stdio: ["pipe", "pipe", "pipe"],
        env,
        shell: true, // needed for npx path resolution
      });

      const timeout = setTimeout(() => {
        reject(new Error(`MCP server "${this.serverName}" start timeout`));
      }, 30000);

      // Read stdout line by line (JSON-RPC uses newline-delimited JSON)
      const rl = createInterface({ input: this.proc.stdout! });
      rl.on("line", (line: string) => {
        try {
          const msg = JSON.parse(line) as JSONRPCResponse;
          const handler = this.pending.get(msg.id);
          if (handler) {
            this.pending.delete(msg.id);
            handler(msg);
          }
        } catch {
          // non-JSON lines (e.g., debug output) are ignored
        }
      });

      // Log stderr for debugging
      this.proc.stderr?.on("data", (d: Buffer) => {
        // silently ignore; MCP spec says servers should not write to stderr
      });

      this.proc.on("error", (err) => {
        clearTimeout(timeout);
        reject(err);
      });

      this.proc.on("exit", (code) => {
        clearTimeout(timeout);
        this.proc = null;
        this.initialized = false;
        if (!this.initialized) {
          reject(new Error(`MCP server "${this.serverName}" exited with code ${code}`));
        }
      });

      // Send initialize
      this.send("initialize", {
        protocolVersion: PREFERRED_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: { name: "pi-mcp-gateway", version: "1.0.0" },
      })
        .then((res) => {
          clearTimeout(timeout);
          if (res.error) {
            reject(new Error(`MCP initialize failed: ${res.error.message}`));
            return;
          }
          // Accept the server's negotiated protocol version.
          const initResult = res.result as { protocolVersion?: string } | undefined;
          this.negotiatedVersion = initResult?.protocolVersion ?? PREFERRED_PROTOCOL_VERSION;
          this.initialized = true;
          // Send initialized notification
          if (this.proc?.stdin) {
            const notif = JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n";
            this.proc.stdin.write(notif);
          }
          resolve();
        })
        .catch(reject);
    });
  }

  private send(method: string, params?: Record<string, unknown>): Promise<JSONRPCResponse> {
    return new Promise((resolve, reject) => {
      if (!this.proc?.stdin) {
        return reject(new Error("MCP client not started"));
      }

      const id = ++this.reqId;
      const req: JSONRPCRequest = { jsonrpc: "2.0", id, method, params };

      this.pending.set(id, resolve);

      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`MCP call "${method}" timed out`));
      }, 60000);

      // Wrap resolve to clear timeout
      const origResolve = resolve;
      this.pending.set(id, (res) => {
        clearTimeout(timeout);
        origResolve(res);
      });

      this.proc.stdin.write(JSON.stringify(req) + "\n");
    });
  }

  async listTools(): Promise<MCPToolDef[]> {
    const res = await this.send("tools/list");
    if (res.error) throw new Error(`tools/list failed: ${res.error.message}`);
    const result = res.result as { tools?: MCPToolDef[] } | undefined;
    return result?.tools ?? [];
  }

  async callTool(name: string, args: Record<string, unknown>): Promise<string> {
    const res = await this.send("tools/call", { name, arguments: args });
    if (res.error) throw new Error(`tools/call failed: ${res.error.message}`);
    const result = res.result as {
      content?: Array<{ type: string; text?: string }>;
      isError?: boolean;
    } | undefined;

    if (result?.isError) {
      const errText = result.content?.map((c) => c.text ?? "").join("\n") ?? "unknown error";
      throw new Error(`MCP tool error: ${errText}`);
    }

    return result?.content
      ?.filter((c) => c.type === "text")
      .map((c) => c.text ?? "")
      .join("\n") ?? "";
  }

  isRunning(): boolean {
    return this.proc !== null && this.proc.exitCode === null;
  }

  stop(): void {
    if (this.proc) {
      this.proc.kill();
      this.proc = null;
      this.initialized = false;
    }
  }
}

// ---------------------------------------------------------------------------
// MCP Manager
// ---------------------------------------------------------------------------

class MCPManager {
  private clients = new Map<string, MCPClient>();
  private tools = new Map<string, { server: string; tool: MCPToolDef }>();
  private initialized = false;

  private config: MCPConfig;
  private cwd: string;

  constructor(cwd: string) {
    this.cwd = cwd;
    this.config = loadConfig(cwd);
  }

  reloadConfig(): void {
    this.config = loadConfig(this.cwd);
  }

  private toolName(server: string, tool: string): string {
    return `mcp_${server}_${tool}`.replace(/[^a-zA-Z0-9_]/g, "_").slice(0, 64);
  }

  async initialize(pi: ExtensionAPI): Promise<void> {
    if (this.initialized) return;
    this.initialized = true;
    this.reloadConfig();

    // Discover tools from enabled servers — start in parallel.
    // Each server is independently started; failures in one do not block others.
    const servers = getEnabledServers(this.config);

    const results = await Promise.allSettled(
      servers.map(async ([name, cfg]) => {
        const client = new MCPClient(cfg, name);
        await client.start();
        this.clients.set(name, client);

        const tools = await client.listTools();
        for (const tool of tools) {
          const tname = this.toolName(name, tool.name);
          this.tools.set(tname, { server: name, tool });
        }
      })
    );

    // Log failures without blocking
    for (let i = 0; i < results.length; i++) {
      const result = results[i];
      if (result.status === "rejected") {
        const [name] = servers[i];
        const msg = result.reason instanceof Error ? result.reason.message : String(result.reason);
        console.error(`[mcp-gateway] Failed to initialize "${name}": ${msg}`);
      }
    }

    // Register pi tools
    this.registerTools(pi);
  }

  private registerTools(pi: ExtensionAPI): void {
    for (const [tname, { server, tool }] of this.tools) {
      const serverCfg = this.config.mcpServers[server];
      const desc = serverCfg?.description ?? server;

      // Build TypeBox schema from JSON schema. Keys listed in the MCP tool's
      // `required` array are registered as non-optional so the LLM is forced to
      // supply them (otherwise every param was Optional → frequent tool errors).
      const props: Record<string, unknown> = {};
      const requiredSet = new Set<string>(tool.inputSchema?.required ?? []);

      if (tool.inputSchema?.properties) {
        for (const [key, val] of Object.entries(tool.inputSchema.properties)) {
          const v = val as Record<string, unknown>;
          const jtype = v.type as string | undefined;
          const description = (v.description as string) ?? "";
          let base;
          if (jtype === "number" || jtype === "integer") {
            base = Type.Number({ description });
          } else if (jtype === "boolean") {
            base = Type.Boolean({ description });
          } else {
            // string, plus default for complex/unknown types
            base = Type.String({ description });
          }
          props[key] = requiredSet.has(key) ? base : Type.Optional(base);
        }
      }

      const schema = Type.Object(props as any);

      pi.registerTool({
        name: tname,
        label: `MCP:${server}/${tool.name}`,
        description: `[MCP:${desc}] ${tool.description ?? tool.name}`,
        promptSnippet: `MCP tool from ${server}: ${tool.description ?? tool.name}`,
        promptGuidelines: [
          `Use ${tname} when you need to access ${server} capabilities.`,
          `Check MCP tool results carefully; they may be truncated.`,
        ],
        parameters: schema,
        execute: async (_toolCallId, params, _signal, onUpdate) => {
          return this.executeTool(server, tool.name, params, onUpdate);
        },
      });
    }
  }

  private async executeTool(
    server: string,
    toolName: string,
    params: Record<string, unknown>,
    onUpdate?: (update: { content: Array<{ type: string; text: string }> }) => void
  ): Promise<{
    content: Array<{ type: string; text: string }>;
    details: Record<string, unknown>;
  }> {
    const serverCfg = this.config.mcpServers[server];

    // Build details for audit (secrets redacted)
    const argsSummary = redactSecrets(JSON.stringify(params)).slice(0, 200);

    onUpdate?.({ content: [{ type: "text", text: `🔌 MCP: ${server}/${toolName}...` }] });

    // Execute
    const startTime = Date.now();
    try {
      const client = this.clients.get(server);
      if (!client || !client.isRunning()) {
        // Try to restart
        if (client) {
          client.stop();
          this.clients.delete(server);
        }
        const newClient = new MCPClient(serverCfg, server);
        await newClient.start();
        this.clients.set(server, newClient);

        // Re-discover tools (in case server changed)
        const tools = await newClient.listTools();
        for (const tool of tools) {
          const tname2 = this.toolName(server, tool.name);
          if (!this.tools.has(tname2)) {
            this.tools.set(tname2, { server, tool });
          }
        }
      }

      const activeClient = this.clients.get(server)!;
      const result = await activeClient.callTool(toolName, params);
      const elapsed = Date.now() - startTime;
      const maxSize = serverCfg?.maxResultSize ?? DEFAULT_MAX_RESULT;
      const trimmed = result.slice(0, maxSize);

      logMCPAudit(server, toolName, argsSummary, "success", undefined, elapsed);
      updateMCPStats(server, "calls", elapsed);

      return {
        content: [{
          type: "text",
          text: `## MCP: ${server}/${toolName} (${elapsed}ms)\n\n${trimmed}${result.length > maxSize ? "\n\n*(truncated)*" : ""}`,
        }],
        details: {
          server,
          tool: toolName,
          status: "success",
          elapsedMs: elapsed,
          resultLength: result.length,
          truncated: result.length > maxSize,
        },
      };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      const elapsed = Date.now() - startTime;

      logMCPAudit(server, toolName, argsSummary, "error", msg, elapsed);
      updateMCPStats(server, "errors", 0);

      return {
        content: [{
          type: "text",
          text: `❌ MCP tool "${server}/${toolName}" failed: ${msg}`,
        }],
        details: {
          server,
          tool: toolName,
          status: "error",
          error: msg,
          elapsedMs: elapsed,
        },
      };
    }
  }

  shutdown(): void {
    for (const [, client] of this.clients) {
      client.stop();
    }
    this.clients.clear();
    this.tools.clear();
    this.initialized = false;
  }

  getTools(): Map<string, { server: string; tool: MCPToolDef }> {
    return this.tools;
  }

}

// ---------------------------------------------------------------------------
// Audit & Stats
// ---------------------------------------------------------------------------

function ensureResearchDir() {
  if (!existsSync(RESEARCH_DIR)) mkdirSync(RESEARCH_DIR, { recursive: true });
}

// Redact obvious secrets before they hit the audit log (MCP tool args can carry
// tokens). Best-effort — covers key/token/password assignments and common token
// shapes, not a guarantee.
function redactSecrets(s: string): string {
  return s
    .replace(/("?(?:api[_-]?key|token|secret|password|authorization)"?\s*[:=]\s*"?)[^",}\s]+/gi, "$1[REDACTED]")
    .replace(/sk-[a-zA-Z0-9]{20,}/g, "[REDACTED]")
    .replace(/gh[pousr]_[a-zA-Z0-9]{20,}/g, "[REDACTED]")
    .replace(/xox[bprs]-[a-zA-Z0-9-]{10,}/g, "[REDACTED]");
}

function logMCPAudit(
  server: string,
  tool: string,
  args: string,
  status: string,
  error?: string,
  elapsedMs?: number
) {
  ensureResearchDir();
  appendFileSync(
    MCP_AUDIT_FILE,
    JSON.stringify({
      timestamp: new Date().toISOString(),
      server,
      tool,
      args: args.slice(0, 500),
      status,
      error: error?.slice(0, 200) ?? null,
      elapsedMs: elapsedMs ?? null,
    }) + "\n"
  );
}

function updateMCPStats(server: string, field: string, elapsedMs: number) {
  ensureResearchDir();
  let stats: Record<string, unknown> = {};
  if (existsSync(MCP_STATS_FILE)) {
    try { stats = JSON.parse(readFileSync(MCP_STATS_FILE, "utf-8")); } catch { /* reset */ }
  }
  const s = (stats[server] as Record<string, number>) ?? {};
  s[field] = (s[field] ?? 0) + 1;
  if (elapsedMs > 0) s.totalMs = (s.totalMs ?? 0) + elapsedMs;
  stats[server] = s;
  writeFileSync(MCP_STATS_FILE, JSON.stringify(stats));
}

// ---------------------------------------------------------------------------
// Extension entry point
// ---------------------------------------------------------------------------

export default async function (pi: ExtensionAPI) {
  const cwd = process.cwd();
  const manager = new MCPManager(cwd);

  // Initialize on startup
  pi.on("session_start", async (_event, ctx) => {
    try {
      await manager.initialize(pi);
      const toolCount = manager.getTools().size;
      if (toolCount > 0) {
        ctx.ui.notify(`MCP Gateway: ${toolCount} tools from ${manager.getTools().size > 0 ? "enabled servers" : "no servers"}`, "info");
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      ctx.ui.notify(`MCP Gateway init failed: ${msg}`, "error");
    }
  });


  // Cleanup on shutdown
  pi.on("session_shutdown", async () => {
    manager.shutdown();
  });

  // Command to list MCP tools
  pi.registerCommand("mcp", {
    description: "List available MCP tools and status",
    handler: async (_args, ctx) => {
      const config = loadConfig(cwd);
      const servers = Object.entries(config.mcpServers);
      if (servers.length === 0) {
        ctx.ui.notify("No MCP servers configured.", "info");
        return;
      }

      const lines: string[] = ["## MCP Servers", ""];
      for (const [name, cfg] of servers) {
        const status = cfg.enabled !== false ? "✅" : "❌";
        lines.push(`- ${status} **${name}** — ${cfg.description ?? "no description"} (policy: pi-permissions)`);
        const tools = [...manager.getTools().entries()]
          .filter(([, v]) => v.server === name);
        for (const [tname] of tools) {
          lines.push(`  - \`${tname}\``);
        }
      }

      // Show the output in a notification (truncated)
      ctx.ui.notify(lines.slice(0, 10).join("\n"), "info");
    },
  });
}
