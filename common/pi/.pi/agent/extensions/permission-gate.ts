// Permission Gate Extension for pi
// Blocks dangerous bash commands pending user confirmation.
// Install: place in ~/.pi/agent/extensions/permission-gate.ts

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Defense-in-depth only. This is a denylist and is inherently bypassable
// (e.g. `rm -r -f`, base64-encoded commands, obscure flag spellings); it is not
// a security boundary. Its job is to catch the obvious-footgun cases and force
// a human decision, not to stop a determined adversary.
const DANGEROUS_PATTERNS = [
  /\brm\b(?=[^|;&\n]*\s-[a-z]*r)(?=[^|;&\n]*\s-[a-z]*f)/i, // rm with both -r and -f (rf/fr/-r -f)
  /\bsudo\b/,
  /chmod\s+(-R\s+)?777/,
  /\bchown\b/,
  /\bdocker\s+system\s+prune\b/,
  /\bkubectl\s+delete\b/,
  /\bterraform\s+(apply|destroy)\b/,
  /\bpnpm\s+publish\b/,
  /\bnpm\s+publish\b/,
  /\bgit\s+push\s+.*--force(-with-lease)?\b/,
  /\bgit\s+reset\s+--hard\b/,
  /\bgit\s+clean\s+-[a-z]*f[a-z]*d|\bgit\s+clean\s+-[a-z]*d[a-z]*f/, // git clean -fd
  /\bdd\s+(if|of)=/,
  /\bmkfs(\.\w+)?\b/,
  />\s*\/dev\/(sd|nvme|disk|hd)/, // overwrite raw block device
  /\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(sh|bash|zsh)\b/, // pipe-to-shell
  /:\s*\(\s*\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:/, // fork bomb
  /\bDROP\s+(TABLE|DATABASE|SCHEMA)\b/i,
  /\bDELETE\s+FROM\b/i,
  /\btruncate\s+table\b/i,
  // Production database protection
  /psql.*-U\s+postgres.*(bstg-syntopic|sandbox-andtopic)/i,
  /PGPASSWORD=.*psql/i,
  /\bINSERT\s+INTO\s+/i,
  /\bUPDATE\s+\w+\s+SET\s+/i,
  /\bCREATE\s+(TABLE|FUNCTION|INDEX|POLICY|ROLE)\s+/i,
  /\bALTER\s+(TABLE|FUNCTION)\s+/i,
  /\bGRANT\s+(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\s+/i,
];

// Tool names that execute shell commands. `bash` is pi's real tool; the others
// are matched defensively (harmless if they don't exist — the gate never fires).
const SHELL_TOOLS = new Set(["bash", "shell", "sh", "exec", "run"]);

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (!SHELL_TOOLS.has(event.toolName)) return;

    const command = String(event.input?.command ?? event.input?.cmd ?? "");
    if (!command) return;

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
