// Statusline Extension for pi
//
// Multi-line footer with:
//   Line 1: token stats + context gauge + cost + branch + model
//   Line 2: web stats + MCP stats
//   3 modes: detailed / compact / off (toggle via /statusline)
//
// The gauge is a plain-character progress bar: ████░░░░░░  29%
// No ANSI codes inside compound strings to avoid truncation issues.

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

/**
 * Plain-character progress gauge. Safe to use inside theme.fg() because the
 * characters have no ANSI codes. Returns something like "████░░░░  29%".
 */
function gauge(pct: number, barChars: number): string {
  const filled = Math.round((pct / 100) * barChars);
  return "█".repeat(filled) + "░".repeat(barChars - filled) + ` ${pct.toFixed(0)}%`;
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
      { value: "detailed", label: "Two-line layout with gauge and all stats" },
      { value: "compact", label: "Single line, minimal" },
      { value: "off", label: "Disable custom statusline" },
    ],
    handler: async (args, ctx) => {
      if (args === "detailed" || args === "compact" || args === "off") {
        mode = args;
      } else {
        const cycle: DisplayMode[] = ["detailed", "compact", "off"];
        mode = cycle[(cycle.indexOf(mode) + 1) % cycle.length];
      }
      if (mode === "off") {
        ctx.ui.setFooter(undefined);
        ctx.ui.notify("Statusline: off", "info");
      } else {
        ctx.ui.notify(`Statusline: ${mode}`, "info");
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
    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsub = footerData.onBranchChange(() => tui.requestRender());
      return {
        dispose: unsub,
        invalidate() {},
        render(width: number): string[] {
          if (mode === "off") return [];

          // ---- Accumulate token stats ----
          let input = 0, output = 0, cost = 0;
          for (const e of ctx.sessionManager.getBranch()) {
            if (e.type === "message" && e.message.role === "assistant") {
              const m = e.message as AssistantMessage;
              input += m.usage.input; output += m.usage.output; cost += m.usage.cost.total;
            }
          }

          // ---- Context ----
          const usage = ctx.getContextUsage();
          const capacity = ctx.model?.contextWindow ?? 0;
          const used = usage?.tokens ?? 0;
          const pct = capacity > 0 ? (used / capacity) * 100 : 0;

          // ---- Stats ----
          const stats = readStats();

          // ---- Git / Model ----
          const branch = footerData.getGitBranch();
          const branchStr = branch
            ? `${theme.fg(dirtyState ? "warning" : "accent", branch)}${dirtyState ? theme.fg("warning", "*") : ""}`
            : "";
          const modelStr = theme.fg("muted", ctx.model?.id || "no-model");

          // ---- Tokens (left side) ----
          const tokIn = theme.fg("text", `↑${formatTokens(input)}`);
          const tokOut = theme.fg("accent", `↓${formatTokens(output)}`);
          const costColor = cost > 1 ? "warning" : cost > 0.1 ? "text" : "dim";
          const tokCost = theme.fg(costColor, `$${cost.toFixed(3)}`);

          // ---- Gauge ----
          const ctxColor = pct > 80 ? "error" : pct > 60 ? "warning" : "success";
          const gaugeStr = capacity > 0
            ? theme.fg(ctxColor, gauge(pct, 10))
            : "";

          // ---- Layout: 3-line, all left-aligned ----
          // Line 1: tokens + gauge + cost
          // Line 2: branch + model
          // Line 3: web stats + mcp stats (only if data exists)

          if (mode === "compact") {
            return [truncateToWidth(`${tokIn} ${tokOut} ${tokCost}  ${modelStr}`, width)];
          }

          const l1 = [tokIn, tokOut, gaugeStr, tokCost].filter(Boolean).join(" │ ");
          const lines = [truncateToWidth(l1, width)];

          const l2 = [branchStr, modelStr].filter(Boolean).join(" · ");
          if (l2) lines.push(truncateToWidth(l2, width));

          const l3: string[] = [];
          if (stats.webSearch > 0 || stats.webFetch > 0) {
            l3.push(theme.fg("dim", `web s:${stats.webSearch} f:${stats.webFetch} c:${stats.webCache}`));
          }
          if (stats.mcpCalls > 0) {
            l3.push(theme.fg("cyan", `mcp q:${stats.mcpCalls}${stats.mcpErrors > 0 ? ` e:${stats.mcpErrors}` : ""}`));
          }
          if (l3.length > 0) lines.push(truncateToWidth(l3.join(" · "), width));

          return lines;
        },
      };
    });
  });
}
