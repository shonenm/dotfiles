// Permission Gate Extension for pi
// Blocks dangerous bash commands pending user confirmation.
// Install: place in ~/.pi/agent/extensions/permission-gate.ts

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const execFileAsync = promisify(execFile);

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
];

// Tool names that execute shell commands. `bash` is pi's real tool; the others
// are matched defensively (harmless if they don't exist — the gate never fires).
const SHELL_TOOLS = new Set(["bash", "shell", "sh", "exec", "run"]);

// The exemption deliberately accepts a tiny shell grammar: a standalone `rm`
// with relative, non-traversing arguments, or a standalone force-push from the
// current repository. Everything else retains the confirmation dialog.
function isRepoLocalRm(command: string): boolean {
  const parts = command.trim().split(/\s+/);
  if (parts.shift() !== "rm") return false;

  let recursive = false;
  let force = false;
  let options = true;
  const targets: string[] = [];
  for (const part of parts) {
    if (options && part === "--") {
      options = false;
    } else if (options && /^-[A-Za-z]+$/.test(part)) {
      recursive ||= part.includes("r") || part.includes("R");
      force ||= part.includes("f");
    } else if (options && part === "--recursive") {
      recursive = true;
    } else if (options && part === "--force") {
      force = true;
    } else {
      targets.push(part);
    }
  }

  return recursive && force && targets.length > 0 && targets.every(
    (target) => !target.startsWith("/") && !target.split("/").includes("..") && !/["'`$;&|()\\]/.test(target),
  );
}

function isRepoLocalForceWithLease(command: string): boolean {
  return /^git\s+push\b(?=[\s\S]*--force-with-lease)[^;&|`$()\n]*$/.test(command.trim());
}

async function isGitWorktree(cwd: string): Promise<boolean> {
  try {
    const { stdout } = await execFileAsync("git", ["-C", cwd, "rev-parse", "--is-inside-work-tree"]);
    return stdout.trim() === "true";
  } catch {
    return false;
  }
}

export async function isTrustedGitProjectCommand(command: string, cwd: string): Promise<boolean> {
  if (!isRepoLocalRm(command) && !isRepoLocalForceWithLease(command)) return false;
  return isGitWorktree(cwd);
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (!SHELL_TOOLS.has(event.toolName)) return;

    const command = String(event.input?.command ?? event.input?.cmd ?? "");
    if (!command) return;

    const matched = DANGEROUS_PATTERNS.find((p) => p.test(command));
    if (!matched) return;

    if (await isTrustedGitProjectCommand(command, ctx.cwd)) return;

    const ok = await ctx.ui.confirm(
      "🛡️ Dangerous command detected",
      `Allow this command?\n\n${command}\n\nPattern matched: ${matched.source}`
    );

    if (!ok) {
      return { block: true, reason: "Blocked by permission-gate extension" };
    }
  });
}
