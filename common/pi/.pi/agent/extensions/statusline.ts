// Statusline Extension for pi
// Replaces the footer with a richer status line showing:
//   - Token stats (input/output/cost)
//   - Git branch + dirty state
//   - Current model
//
// Toggle via /statusline command.

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { execSync } from "node:child_process";

let enabled = true;
let dirtyState = false;
let lastDirtyCheck = 0;
const DIRTY_CHECK_INTERVAL_MS = 5000;

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
  if (n < 1000000) return `${(n / 1000).toFixed(1)}k`;
  return `${(n / 1000000).toFixed(1)}M`;
}

export default function (pi: ExtensionAPI) {
  // Toggle command
  pi.registerCommand("statusline", {
    description: "Toggle custom statusline footer",
    handler: async (_args, ctx) => {
      enabled = !enabled;
      if (enabled) {
        ctx.ui.notify("Statusline enabled", "info");
      } else {
        ctx.ui.setFooter(undefined);
        ctx.ui.notify("Default footer restored", "info");
      }
    },
  });

  // Update dirty state after each turn (user has likely made edits)
  pi.on("turn_end", async () => {
    if (!enabled) return;
    const now = Date.now();
    if (now - lastDirtyCheck > DIRTY_CHECK_INTERVAL_MS) {
      dirtyState = checkGitDirty();
      lastDirtyCheck = now;
    }
  });

  // Also check on session start
  pi.on("session_start", async () => {
    if (!enabled) return;
    dirtyState = checkGitDirty();
    lastDirtyCheck = Date.now();
  });

  // Install custom footer on session start
  pi.on("session_start", async (_event, ctx) => {
    if (!enabled) return;

    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsub = footerData.onBranchChange(() => tui.requestRender());

      return {
        dispose: unsub,
        invalidate() {},
        render(width: number): string[] {
          // Token stats from session branch
          let input = 0,
            output = 0,
            cost = 0;
          for (const e of ctx.sessionManager.getBranch()) {
            if (e.type === "message" && e.message.role === "assistant") {
              const m = e.message as AssistantMessage;
              input += m.usage.input;
              output += m.usage.output;
              cost += m.usage.cost.total;
            }
          }

          // Git branch with color
          const branch = footerData.getGitBranch();
          const branchColor = dirtyState ? "warning" : "accent";
          const branchStr = branch
            ? ` ${theme.fg(branchColor, branch)}${dirtyState ? theme.fg("warning", "*") : ""} `
            : "";

          // Model
          const modelStr = theme.fg("muted", ctx.model?.id || "no-model");

          // Context capacity with color based on usage
          const usage = ctx.getContextUsage();
          const capacity = ctx.model?.contextWindow ?? 0;
          const used = usage?.tokens ?? 0;
          const pct = capacity > 0 ? (used / capacity) * 100 : 0;
          const ctxColor = pct > 80 ? "error" : pct > 60 ? "warning" : "success";
          const ctxStr =
            capacity > 0
              ? theme.fg(ctxColor, `${formatTokens(used)}/${formatTokens(capacity)} (${pct.toFixed(0)}%)`)
              : "";

          // Left: colorful token stats
          const inputStr = theme.fg("info", `↑${formatTokens(input)}`);
          const outputStr = theme.fg("accent", `↓${formatTokens(output)}`);
          const costStr = theme.fg("success", `$${cost.toFixed(3)}`);

          const leftParts = [inputStr, outputStr, costStr];
          if (ctxStr) leftParts.push(ctxStr);
          const left = leftParts.join(" ");

          // Right: branch + model
          const right = `${branchStr}${modelStr}`.trimStart();

          const padWidth = Math.max(
            1,
            width - visibleWidth(left) - visibleWidth(right)
          );
          const pad = " ".repeat(padWidth);

          return [truncateToWidth(left + pad + right, width)];
        },
      };
    });
  });
}
