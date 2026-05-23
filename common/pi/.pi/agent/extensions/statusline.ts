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

          // ---- Layout: progressive hiding from right to left as width decreases ----
          // Elements from right to left (first to hide → last to hide):
          //   model → branch → mcp stats → web stats → context gauge → cost → output → input

          if (mode === "compact") {
            // Compact: minimal, always single line
            const left = `${segIn} ${segOut} ${segCost}`;
            const right = [modelStr].join(" ");
            const pad = Math.max(1, width - visibleWidth(left) - visibleWidth(right));
            return [truncateToWidth(left + " ".repeat(pad) + right, width)];
          }

          // Detailed: progressive layout
          // Build a single line, dropping elements from right as space shrinks.
          // Use color ONLY on simple tokens (no ANSI inside compound strings that get truncated).
          const lines: string[] = [];

          // Left base: always show tokens
          const leftBase = `${segIn} ${segOut} ${segCost}`;

          // Context gauge (simple text, pre-colored via ctxColor)
          const ctxGauge = capacity > 0
            ? ` ${theme.fg(ctxColor, `[${pct.toFixed(0)}%]`)}`
            : "";

          // Right elements in priority order (first to drop = rightmost)
          const rightElems: string[] = [];
          if (branchStr) rightElems.push(branchStr);
          if (stats.webSearch > 0 || stats.webFetch > 0) {
            rightElems.push(theme.fg("dim", `web s:${stats.webSearch} f:${stats.webFetch} c:${stats.webCache}`));
          }
          if (stats.mcpCalls > 0) {
            rightElems.push(theme.fg("cyan", `mcp q:${stats.mcpCalls}${stats.mcpErrors > 0 ? ` e:${stats.mcpErrors}` : ""}`));
          }
          rightElems.push(modelStr);

          // Try fitting everything on one line. If not, drop elements or fall back to two lines.
          const fullLeft = leftBase + ctxGauge;
          const fullRight = rightElems.join(" ");
          const fullWidth = visibleWidth(fullLeft) + visibleWidth(fullRight) + 1;

          if (fullWidth <= width) {
            // Everything fits on one line
            const pad = " ".repeat(width - visibleWidth(fullLeft) - visibleWidth(fullRight));
            lines.push(fullLeft + pad + fullRight);
          } else {
            // Doesn't fit. Try dropping right elements one by one.
            let dropped = false;
            for (let i = rightElems.length; i >= 0; i--) {
              const r = rightElems.slice(0, i).join(" ");
              const w = visibleWidth(fullLeft) + (r ? visibleWidth(r) + 1 : 0);
              if (w <= width) {
                const pad = r ? " ".repeat(width - visibleWidth(fullLeft) - visibleWidth(r)) : "";
                lines.push(fullLeft + (r ? pad + r : ""));
                dropped = true;
                break;
              }
            }
            if (!dropped) {
              // Even tokens alone don't fit — minimal fallback
              lines.push(truncateToWidth(leftBase, width));
            }
          }

          return lines;
        },
      };
    });
  });
}
