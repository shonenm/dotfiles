// Quick Question Extension for pi
//
// /q <question> — ask a side question without polluting conversation history.
// Spawns a separate pi instance via pi -p, shows result as notification.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("btw", {
    description: "Ask a quick side question (won't pollute conversation)",
    handler: async (args, ctx) => {
      if (!args) {
        ctx.ui.notify("Usage: /btw <question>", "error");
        return;
      }

      ctx.ui.notify(`Asking: ${args.slice(0, 60)}...`, "info");

      try {
        const escaped = args.replace(/'/g, "'\\''");
        const result = execSync(
          `pi --model 'opencode-go/deepseek-v4-flash:off' -p '${escaped}' < /dev/null 2>&1`,
          { encoding: "utf-8", timeout: 30_000, stdio: ["pipe", "pipe", "pipe"] }
        );

        // Show first non-warning line as answer
        const lines = result.split("\n").filter((l) =>
          !l.startsWith("Warning:") && l.trim().length > 0
        );
        const answer = lines.join(" ").slice(0, 300);

        ctx.ui.notify(answer || "(no output)", "info");
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        ctx.ui.notify(`Failed: ${msg.slice(0, 100)}`, "error");
      }
    },
  });
}
