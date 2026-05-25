// Session Manager Extension for pi
//
// Session naming, listing, import/export.
// Auto-names sessions from git branch + first prompt.

import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { existsSync, readFileSync, writeFileSync, readdirSync } from "node:fs";
import { execSync } from "node:child_process";
import { homedir } from "node:os";
import { join, basename, dirname } from "node:path";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SESSION_DIR = join(homedir(), ".pi", "agent", "sessions");

function listSessions(): Array<{ file: string; name: string; cwd: string; modified: string }> {
  const dirs = [SESSION_DIR, join(process.cwd(), ".pi", "sessions")];
  const results: Array<{ file: string; name: string; cwd: string; modified: string }> = [];

  function scan(dir: string) {
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) {
        scan(full);
      } else if (entry.name.endsWith(".jsonl")) {
        try {
          const firstLine = readFileSync(full, "utf-8").split("\n")[0];
          const header = JSON.parse(firstLine);
          results.push({
            file: full,
            name: header.sessionName || basename(full, ".jsonl"),
            cwd: header.cwd || "",
            modified: entry.name.slice(0, 19),
          });
        } catch {
          results.push({ file: full, name: basename(full, ".jsonl"), cwd: "", modified: "" });
        }
      }
    }
  }

  for (const dir of dirs) scan(dir);
  return results.sort((a, b) => b.modified.localeCompare(a.modified));
}

function gitBranchName(): string | null {
  try {
    return execSync("git branch --show-current", {
      encoding: "utf-8", timeout: 2000,
      stdio: ["pipe", "pipe", "ignore"],
    }).trim() || null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  // -----------------------------------------------------------------------
  // Auto-name session on start
  // -----------------------------------------------------------------------
  pi.on("session_start", async (_event, ctx) => {
    const existing = pi.getSessionName();
    if (existing) return;

    const branch = gitBranchName();
    if (branch) {
      pi.setSessionName(branch);
    }
  });

  // -----------------------------------------------------------------------
  // Command: /session-name <name>
  // -----------------------------------------------------------------------
  pi.registerCommand("session-name", {
    description: "Set the current session display name",
    handler: async (args, ctx) => {
      if (!args) {
        const name = pi.getSessionName();
        ctx.ui.notify(name ? `Session: ${name}` : "No name set", "info");
        return;
      }
      pi.setSessionName(args);
      ctx.ui.notify(`Session renamed: ${args}`, "info");
    },
  });

  // -----------------------------------------------------------------------
  // Command: /sessions
  // -----------------------------------------------------------------------
  pi.registerCommand("sessions", {
    description: "List recent sessions",
    handler: async (_args, ctx) => {
      const sessions = listSessions();
      if (sessions.length === 0) {
        ctx.ui.notify("No sessions found", "info");
        return;
      }

      const lines = sessions.slice(0, 20).map((s, i) =>
        `${i + 1}. ${s.name} (${s.cwd || "?"}) — ${s.modified.slice(0, 16)}`
      );

      ctx.ui.notify(lines.join("\n"), "info");
    },
  });

  // -----------------------------------------------------------------------
  // Command: /session-export
  // -----------------------------------------------------------------------
  pi.registerCommand("session-export", {
    description: "Export current session to a JSONL file",
    handler: async (args, ctx) => {
      const src = ctx.sessionManager.getSessionFile();
      if (!src) {
        ctx.ui.notify("No session file to export (ephemeral session)", "error");
        return;
      }
      const dest = args || `${basename(src)}`;
      try {
        writeFileSync(dest, readFileSync(src));
        ctx.ui.notify(`Exported: ${dest}`, "info");
      } catch {
        ctx.ui.notify("Export failed", "error");
      }
    },
  });

  // -----------------------------------------------------------------------
  // Command: /session-import <file>
  // -----------------------------------------------------------------------
  pi.registerCommand("session-import", {
    description: "Import a JSONL session file",
    handler: async (args, ctx) => {
      if (!args || !existsSync(args)) {
        ctx.ui.notify("Usage: /session-import <file.jsonl>", "error");
        return;
      }
      const dest = join(SESSION_DIR, basename(args));
      writeFileSync(dest, readFileSync(args));
      ctx.ui.notify(`Imported: ${basename(args)} → sessions/`, "info");
    },
  });
}
