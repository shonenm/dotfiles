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

          // Git branch
          const branch = footerData.getGitBranch();
          const branchStr = branch
            ? ` ${branch}${dirtyState ? "*" : ""} `
            : "";

          // Model
          const modelStr = ctx.model?.id || "no-model";

          // Left: tokens
          const left = theme.fg(
            "dim",
            `↑${formatTokens(input)} ↓${formatTokens(output)} $${cost.toFixed(3)}`
          );

          // Right: branch + model
          const right = theme.fg("dim", `${branchStr}${modelStr}`).trimStart();

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
