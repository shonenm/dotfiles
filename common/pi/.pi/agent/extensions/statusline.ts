// Statusline Extension for pi
//
// Balanced telemetry footer with:
//   Focus rail: goal + extension status
//   Core rail: branch + model | context gauge
//   Telemetry rail: tokens | cost | agents | web | MCP
//   3 modes: detailed / compact / off (toggle via /statusline)

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { execSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

type DisplayMode = "off" | "compact" | "detailed";

// Persist the chosen mode across sessions.
const MODE_FILE = join(homedir(), ".pi", "agent", "statusline-mode");
function loadMode(): DisplayMode {
  try {
    const v = readFileSync(MODE_FILE, "utf-8").trim();
    if (v === "off" || v === "compact" || v === "detailed") return v;
  } catch { /* default below */ }
  return "detailed";
}
function saveMode(m: DisplayMode): void {
  try { writeFileSync(MODE_FILE, m); } catch { /* non-fatal */ }
}

let mode: DisplayMode = loadMode();
let dirtyState = false;
let lastDirtyCheck = 0;
const DIRTY_CHECK_INTERVAL_MS = 5000;

// Cached token totals — recomputed on turn_end / session_start instead of
// re-summing the entire branch on every footer render (cheap on large sessions).
let tokCache = { input: 0, output: 0, cost: 0 };
function recomputeTokens(branch: Iterable<{ type: string; message?: { role: string } }>): void {
  let input = 0, output = 0, cost = 0;
  for (const e of branch) {
    if (e.type === "message" && e.message?.role === "assistant") {
      const m = e.message as unknown as AssistantMessage;
      input += m.usage.input; output += m.usage.output; cost += m.usage.cost.total;
    }
  }
  tokCache = { input, output, cost };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function checkGitDirty(): boolean {
  try {
    const output = execSync("git status --porcelain", {
      encoding: "utf-8", timeout: 1000,
      stdio: ["pipe", "pipe", "ignore"],
    });
    return output.trim().length > 0;
  } catch { return false; }
}

function formatTokens(n: number): string {
  if (n < 1000) return `${n}`;
  if (n < 1_000_000) return `${(n / 1000).toFixed(1)}k`;
  return `${(n / 1_000_000).toFixed(1)}M`;
}

interface StatsSnapshot {
  webSearch: number; webFetch: number; webCache: number;
  mcpCalls: number; mcpErrors: number;
}

let cachedStats: StatsSnapshot | null = null;
let statsCacheMs = 0;
const STATS_CACHE_TTL = 10_000;

function readStats(): StatsSnapshot {
  const now = Date.now();
  if (cachedStats && now - statsCacheMs < STATS_CACHE_TTL) return cachedStats;
  const s: StatsSnapshot = { webSearch: 0, webFetch: 0, webCache: 0, mcpCalls: 0, mcpErrors: 0 };
  const dir = join(homedir(), ".pi", "research");
  try {
    const ws = JSON.parse(readFileSync(join(dir, "stats.json"), "utf-8"));
    s.webSearch = ws.searchCount ?? 0; s.webFetch = ws.fetchCount ?? 0; s.webCache = ws.cacheHits ?? 0;
  } catch { /* ignore */ }
  try {
    const ms = JSON.parse(readFileSync(join(dir, "mcp-stats.json"), "utf-8"));
    for (const [, v] of Object.entries(ms) as [string, { calls?: number; errors?: number }][]) {
      s.mcpCalls += v.calls ?? 0; s.mcpErrors += v.errors ?? 0;
    }
  } catch { /* ignore */ }
  cachedStats = s; statsCacheMs = now;
  return s;
}

// Pinned session note (set via /pin-goal in the memory extension). Tiny file — read directly.
const GOAL_FILE = join(homedir(), ".pi", "agent", "goal");
function readGoal(): string {
  try { return readFileSync(GOAL_FILE, "utf-8").trim(); } catch { return ""; }
}

// Active delegated sub-agents (pueue tasks labeled pi-delegate). Refreshed off
// the render path (turn_end / session_start) since `pueue status` shells out.
let agentStatus = { running: 0, queued: 0 };
function refreshAgents(): void {
  let running = 0, queued = 0;
  try {
    const out = execSync("pueue status --json", {
      encoding: "utf-8", timeout: 1500, stdio: ["pipe", "pipe", "ignore"],
    });
    const data = JSON.parse(out);
    const tasks = (data.tasks ?? {}) as Record<string, { label?: string; status?: unknown }>;
    for (const id of Object.keys(tasks)) {
      const t = tasks[id];
      if (t?.label !== "pi-delegate") continue;
      const state = typeof t.status === "string" ? t.status : Object.keys(t.status ?? {})[0];
      if (state === "Running") running++;
      else if (state === "Queued" || state === "Paused") queued++;
    }
  } catch { /* pueue not running / unparseable — show nothing */ }
  agentStatus = { running, queued };
}

function balanceLine(left: string, right: string, width: number): string {
  if (!left) return truncateToWidth(right, width);
  if (!right) return truncateToWidth(left, width);

  const gap = 3;
  const rightWidth = visibleWidth(right);
  if (rightWidth >= width - gap) return truncateToWidth(right, width);

  const fittedLeft = truncateToWidth(left, width - rightWidth - gap);
  const padding = " ".repeat(Math.max(gap, width - visibleWidth(fittedLeft) - rightWidth));
  return truncateToWidth(fittedLeft + padding + right, width);
}

function wrapGroups(groups: string[], width: number, separator = " │ "): string[] {
  const lines: string[] = [];
  let line = "";

  for (const group of groups.filter(Boolean)) {
    const candidate = line ? line + separator + group : group;
    if (line && visibleWidth(candidate) > width) {
      lines.push(truncateToWidth(line, width));
      line = group;
    } else {
      line = candidate;
    }
  }
  if (line) lines.push(truncateToWidth(line, width));
  return lines;
}

function packCompact(groups: string[], width: number, separator = " · "): string {
  let line = "";
  for (const group of groups.filter(Boolean)) {
    const candidate = line ? line + separator + group : group;
    if (visibleWidth(candidate) <= width) line = candidate;
  }
  return truncateToWidth(line || groups.find(Boolean) || "", width);
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  // -----------------------------------------------------------------------
  // Command: /statusline [detailed|compact|off]
  // -----------------------------------------------------------------------
  pi.registerCommand("statusline", {
    description: "Toggle statusline mode: detailed, compact, or off",
    getArgumentCompletions: () => [
      { value: "detailed", label: "Balanced rich telemetry rails" },
      { value: "compact", label: "Single line, minimal" },
      { value: "off", label: "Disable custom statusline" },
    ],
    handler: async (args, ctx) => {
      const previousMode = mode;
      if (args === "detailed" || args === "compact" || args === "off") {
        mode = args;
      } else {
        const cycle: DisplayMode[] = ["detailed", "compact", "off"];
        mode = cycle[(cycle.indexOf(mode) + 1) % cycle.length];
      }
      saveMode(mode);
      if (mode === "off") {
        ctx.ui.setFooter(undefined);
        ctx.ui.notify("Statusline: off", "info");
      } else if (previousMode === "off") {
        await ctx.reload();
        return;
      } else {
        ctx.ui.notify(`Statusline: ${mode}`, "info");
      }
    },
  });

  // -----------------------------------------------------------------------
  // Git dirty check
  // -----------------------------------------------------------------------
  pi.on("turn_end", async (_event, ctx) => {
    if (mode === "off") return;
    recomputeTokens(ctx.sessionManager.getBranch());
    refreshAgents();
    const now = Date.now();
    if (now - lastDirtyCheck > DIRTY_CHECK_INTERVAL_MS) {
      dirtyState = checkGitDirty(); lastDirtyCheck = now;
    }
  });
  pi.on("session_start", async () => {
    if (mode === "off") return;
    dirtyState = checkGitDirty(); lastDirtyCheck = Date.now();
  });

  // -----------------------------------------------------------------------
  // Footer renderer
  // -----------------------------------------------------------------------
  pi.on("session_start", async (_event, ctx) => {
    recomputeTokens(ctx.sessionManager.getBranch());
    refreshAgents();
    if (mode === "off") {
      ctx.ui.setFooter(undefined);
      return;
    }
    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsub = footerData.onBranchChange(() => tui.requestRender());
      return {
        dispose: unsub,
        invalidate() {},
        render(width: number): string[] {
          if (mode === "off") return [];

          // ---- Token stats (cached; recomputed on turn_end / session_start) ----
          const { input, output, cost } = tokCache;

          // ---- Context ----
          const usage = ctx.getContextUsage();
          const rawUsedPct = usage?.percent;
          const usedPct = rawUsedPct === null || rawUsedPct === undefined
            ? null
            : Math.max(0, Math.min(100, rawUsedPct));
          const gaugeChars = width >= 100 ? 10 : width >= 70 ? 8 : 6;
          const ctxColor = usedPct === null
            ? "muted"
            : usedPct >= 85
              ? "error"
              : usedPct >= 70
                ? "warning"
                : "success";
          const filled = usedPct === null ? 0 : Math.round((usedPct / 100) * gaugeChars);
          const pctText = usedPct === null ? "?" : `${usedPct.toFixed(0)}%`;
          const gaugeStr = [
            theme.fg("muted", "CTX"),
            theme.fg(ctxColor, "█".repeat(filled)) + theme.fg("dim", "░".repeat(gaugeChars - filled)),
            theme.fg(ctxColor, pctText),
          ].join(" ");

          // ---- Stats ----
          const stats = readStats();

          // ---- Visual grammar ----
          const minor = theme.fg("dim", " · ");
          const major = theme.fg("dim", " │ ");
          const label = (text: string) => theme.fg("muted", text);

          // ---- Focus rail ----
          const goal = readGoal();
          const goalStr = goal
            ? `${theme.fg("accent", "▌")} ${label("Goal:")} ${theme.fg("text", goal)}`
            : "";
          const extensionStatuses = [...footerData.getExtensionStatuses().values()];
          const statusStr = extensionStatuses.join(minor);

          // ---- Core rail ----
          const branch = footerData.getGitBranch();
          const branchStr = branch
            ? theme.fg(dirtyState ? "warning" : "border", `${branch}${dirtyState ? "*" : ""}`)
            : "";
          const modelStr = theme.fg("customMessageLabel", ctx.model?.id || "no-model");
          const projectStr = [branchStr, modelStr].filter(Boolean).join(minor);

          // ---- Telemetry rail ----
          const tokIn = theme.fg("text", `↑${formatTokens(input)}`);
          const tokOut = theme.fg("accent", `↓${formatTokens(output)}`);
          const tokenStr = `${label("TOK")} ${tokIn}${minor}${tokOut}`;
          const costStr = `${label("COST")} ${theme.fg("syntaxNumber", `$${cost.toFixed(3)}`)}`;
          const agentStr = agentStatus.running > 0 || agentStatus.queued > 0
            ? `${label("AGT")} ${theme.fg("customMessageLabel", `R${agentStatus.running}`)}${minor}${theme.fg("customMessageLabel", `Q${agentStatus.queued}`)}`
            : "";
          const webStr = stats.webSearch > 0 || stats.webFetch > 0
            ? `${label("WEB")} ${theme.fg("syntaxType", `S${stats.webSearch}`)}${minor}${theme.fg("syntaxType", `F${stats.webFetch}`)}${minor}${theme.fg("syntaxType", `C${stats.webCache}`)}`
            : "";
          const mcpError = stats.mcpErrors > 0
            ? minor + theme.fg("error", `E${stats.mcpErrors}`)
            : "";
          const mcpStr = stats.mcpCalls > 0 || stats.mcpErrors > 0
            ? `${label("MCP")} ${theme.fg("border", `Q${stats.mcpCalls}`)}${mcpError}`
            : "";

          if (mode === "compact") {
            const compactFocus = truncateToWidth(
              [statusStr, goalStr].filter(Boolean).join(minor),
              width >= 100 ? 36 : width >= 70 ? 24 : 14,
            );
            return [packCompact(
              [compactFocus, gaugeStr, branchStr, modelStr, tokenStr, costStr],
              width,
              minor,
            )];
          }

          const lines: string[] = [];
          if (goalStr || statusStr) lines.push(balanceLine(goalStr, statusStr, width));
          lines.push(balanceLine(projectStr, gaugeStr, width));
          lines.push(...wrapGroups([tokenStr, costStr, agentStr, webStr, mcpStr], width, major));
          return lines;
        },
      };
    });
  });
}
