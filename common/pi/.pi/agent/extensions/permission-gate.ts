// Permission Gate Extension for pi
// Blocks dangerous bash commands pending user confirmation.
// Install: place in ~/.pi/agent/extensions/permission-gate.ts

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const DANGEROUS_PATTERNS = [
  /rm\s+-rf/,
  /\bsudo\b/,
  /chmod\s+(-R\s+)?777/,
  /\bchown\b/,
  /\bdocker\s+system\s+prune\b/,
  /\bkubectl\s+delete\b/,
  /\bterraform\s+apply\b/,
  /\bpnpm\s+publish\b/,
  /\bnpm\s+publish\b/,
  /\bgit\s+push\s+--force\b/,
  /\bgit\s+reset\s+--hard\b/,
  /\b DROP\s+/i,
  /\b DELETE\s+FROM\s+/i,
  /\btruncate\s+table\b/i,
];

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return;

    const command = String(event.input?.command ?? "");

    const matched = DANGEROUS_PATTERNS.find((p) => p.test(command));
    if (!matched) return;

    const ok = await ctx.ui.confirm(
      "🛡️ Dangerous command detected",
      `Allow this command?\n\n${command}\n\nPattern matched: ${matched.source}`
    );

    if (!ok) {
      return { block: true, reason: "Blocked by permission-gate extension" };
    }
  });
}
