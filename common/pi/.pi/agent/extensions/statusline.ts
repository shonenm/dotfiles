// Statusline Extension for pi
//
// Enhanced footer with:
//   - 3 display modes: detailed / compact / off (toggle via /statusline)
//   - Color-coded token stats (green/yellow/red by context usage)
//   - Visual context progress bar: [======>  ] 45%
//   - MCP activity stats alongside web stats
//   - Multi-line layout when width is insufficient
//   - Unified stats reading from ~/.pi/research/

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

type DisplayMode = "off" | "compact" | "detailed";
let mode: DisplayMode = "detailed";
let dirtyState = false;
let lastDirtyCheck = 0;
const DIRTY_CHECK_INTERVAL_MS = 5000;
const MIN_WIDTH_COMPACT = 60;
const MIN_WIDTH_SINGLE = 100;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function checkGitDirty(): boolean {
  try {
    const output = execSync("git status --porcelain", {
      encoding: "utf-8",
      timeout: 1000,
      stdio: ["pipe", "pipe", "ignore"],
    });
    return output.trim().length > 0;
  } catch {
    return false;
  }
}

function formatTokens(n: number): string {
  if (n < 1000) return `${n}`;
  if (n < 1_000_000) return `${(n / 1000).toFixed(1)}k`;
  return `${(n / 1_000_000).toFixed(1)}M`;
}

interface StatsSnapshot {
  webSearch: number;
  webFetch: number;
  webCache: number;
  webCite: number;
  mcpCalls: number;
  mcpErrors: number;
  mcpServers: number;
}

let cachedStats: StatsSnapshot | null = null;
let statsCacheMs = 0;
const STATS_CACHE_TTL = 10_000;

function readStats(): StatsSnapshot {
  const now = Date.now();
  if (cachedStats && now - statsCacheMs < STATS_CACHE_TTL) return cachedStats;

  const stats: StatsSnapshot = {
    webSearch: 0, webFetch: 0, webCache: 0, webCite: 0,
    mcpCalls: 0, mcpErrors: 0, mcpServers: 0,
  };

  const dir = join(homedir(), ".pi", "research");

  // Web stats
  try {
    const ws = JSON.parse(readFileSync(join(dir, "stats.json"), "utf-8"));
    stats.webSearch = ws.searchCount ?? 0;
    stats.webFetch = ws.fetchCount ?? 0;
    stats.webCache = ws.cacheHits ?? 0;
    stats.webCite = ws.citationCount ?? 0;
  } catch { /* ignore */ }

  // MCP stats
  try {
    const ms = JSON.parse(readFileSync(join(dir, "mcp-stats.json"), "utf-8"));
    for (const [, v] of Object.entries(ms) as [string, { calls?: number; errors?: number; totalMs?: number }][]) {
      stats.mcpCalls += v.calls ?? 0;
      stats.mcpErrors += v.errors ?? 0;
    }
    stats.mcpServers = Object.keys(ms).length;
  } catch { /* ignore */ }

  cachedStats = stats;
  statsCacheMs = now;
  return stats;
}

function contextBar(pct: number, width: number, theme: any): string {
  const barWidth = Math.max(4, width);
  const filled = Math.round((pct / 100) * barWidth);
  const arrow = filled > 0 && filled < barWidth ? ">" : "";
  const bar = "=".repeat(Math.max(0, filled - (arrow ? 1 : 0))) + arrow + " ".repeat(Math.max(0, barWidth - filled));
  const color = pct > 80 ? "error" : pct > 60 ? "warning" : "success";
  return theme.fg(color, `[${bar}]`) + ` ${pct.toFixed(0)}%`;
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
      { value: "detailed", label: "Full info with progress bar" },
      { value: "compact", label: "Minimal (model + branch + token count)" },
      { value: "off", label: "Disable custom statusline" },
    ],
    handler: async (args, ctx) => {
      if (args === "detailed" || args === "compact" || args === "off") {
        mode = args;
      } else {
        // Cycle: detailed → compact → off → detailed
        const cycle: DisplayMode[] = ["detailed", "compact", "off"];
        const idx = cycle.indexOf(mode);
        mode = cycle[(idx + 1) % cycle.length];
      }

      if (mode === "off") {
        ctx.ui.setFooter(undefined);
        ctx.ui.notify("Statusline: off (default footer)", "info");
      } else if (mode === "compact") {
        ctx.ui.notify("Statusline: compact mode", "info");
      } else {
        ctx.ui.notify("Statusline: detailed mode", "info");
      }
    },
  });

  // -----------------------------------------------------------------------
  // Git dirty check
  // -----------------------------------------------------------------------
  pi.on("turn_end", async () => {
    if (mode === "off") return;
    const now = Date.now();
    if (now - lastDirtyCheck > DIRTY_CHECK_INTERVAL_MS) {
      dirtyState = checkGitDirty();
      lastDirtyCheck = now;
    }
  });

  pi.on("session_start", async () => {
    if (mode === "off") return;
    dirtyState = checkGitDirty();
    lastDirtyCheck = Date.now();
  });

  // -----------------------------------------------------------------------
  // Footer renderer
  // -----------------------------------------------------------------------
  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsub = footerData.onBranchChange(() => tui.requestRender());

      return {
        dispose: unsub,
        invalidate() {},
        render(width: number): string[] {
          if (mode === "off") return [];

          // ---- Token stats ----
          let input = 0, output = 0, cost = 0;
          for (const e of ctx.sessionManager.getBranch()) {
            if (e.type === "message" && e.message.role === "assistant") {
              const m = e.message as AssistantMessage;
              input += m.usage.input;
              output += m.usage.output;
              cost += m.usage.cost.total;
            }
          }

          // ---- Context ----
          const usage = ctx.getContextUsage();
          const capacity = ctx.model?.contextWindow ?? 0;
          const used = usage?.tokens ?? 0;
          const pct = capacity > 0 ? (used / capacity) * 100 : 0;

          // ---- Stats ----
          const stats = readStats();

          // ---- Git ----
          const branch = footerData.getGitBranch();
          const branchColor = dirtyState ? "warning" : "accent";
          const branchStr = branch
            ? `${theme.fg(branchColor, branch)}${dirtyState ? theme.fg("warning", "*") : ""}`
            : "";

          // ---- Model ----
          const modelStr = theme.fg("muted", ctx.model?.id || "no-model");

          // ---- Color-coded segments ----
          const costColor = cost > 1 ? "warning" : cost > 0.1 ? "text" : "dim";
          const ctxColor = pct > 80 ? "error" : pct > 60 ? "warning" : "success";

          // ---- Left side ----
          const segIn = theme.fg("text", `↑${formatTokens(input)}`);
          const segOut = theme.fg("accent", `↓${formatTokens(output)}`);
          const segCost = theme.fg(costColor, `$${cost.toFixed(3)}`);

          // ---- Right segments ----
          const parts: string[] = [];

          // Web stats
          if (stats.webSearch > 0 || stats.webFetch > 0) {
            parts.push(theme.fg("dim", `web s:${stats.webSearch} f:${stats.webFetch} c:${stats.webCache}`));
          }

          // MCP stats
          if (stats.mcpCalls > 0) {
            parts.push(theme.fg("cyan", `mcp q:${stats.mcpCalls}${stats.mcpErrors > 0 ? `×${stats.mcpErrors}` : ""}`));
          }

          if (branchStr) parts.push(branchStr);
          parts.push(modelStr);

          // ---- Layout ----
          if (mode === "compact" || width < MIN_WIDTH_COMPACT) {
            // Compact: single line, minimal
            const left = `${segIn} ${segOut} ${segCost}`;
            const right = [...parts, modelStr].filter(Boolean).join(" ");
            const pad = Math.max(1, width - visibleWidth(left) - visibleWidth(right));
            return [truncateToWidth(left + " ".repeat(pad) + right, width)];
          }

          // Detailed: full layout
          const ctxBar = capacity > 0
            ? contextBar(pct, Math.min(20, Math.floor(width * 0.15)), theme)
            : "";

          const left = [segIn, segOut, segCost, ctxBar].filter(Boolean).join(" ");
          const right = parts.join(" ");

          if (width >= MIN_WIDTH_SINGLE) {
            // Single line
            const pad = Math.max(1, width - visibleWidth(left) - visibleWidth(right));
            return [truncateToWidth(left + " ".repeat(pad) + right, width)];
          }

          // Multi-line: stats on separate line when narrow
          return [
            truncateToWidth(left, width),
            truncateToWidth(" ".repeat(Math.max(0, width - visibleWidth(right))) + right, width),
          ];
        },
      };
    });
  });
}
