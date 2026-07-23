// Prompt Stash Extension for pi
//
// Claude Code-like prompt stash: Ctrl+S saves the current editor draft,
// handles an interruption, then auto-restores when the agent settles.
//
// Flow:
//   1. Ctrl+S  → stash current draft + clear editor
//   2. Send a different prompt (handle interruption)
//   3. Agent settles → draft auto-restores into editor
//   4. Continue where you left off
//
// Single-slot stash. Ctrl+S on empty editor toggles restore.
// /stash-clear to discard without restoring. /stash to show status.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  let stashed: string | null = null;

  // -----------------------------------------------------------------------
  // Ctrl+S: stash or restore
  // -----------------------------------------------------------------------
  pi.registerShortcut("ctrl+s", {
    description: "Stash or restore prompt draft",
    handler: async (ctx) => {
      const current = ctx.ui.getEditorText();

      if (current.trim().length > 0) {
        // Stash the current draft (replace any previous stash)
        stashed = current;
        ctx.ui.setEditorText("");
        ctx.ui.setStatus("stash", ctx.ui.theme.fg("warning", "📝 stashed"));
        ctx.ui.notify("📝 Prompt stashed (send interruption, draft auto-restores)", "info");
      } else if (stashed) {
        // Toggle: restore the stash
        ctx.ui.setEditorText(stashed);
        ctx.ui.setStatus("stash", undefined);
        ctx.ui.notify("📝 Stash manually restored", "info");
        stashed = null;
      }
    },
  });

  // -----------------------------------------------------------------------
  // Auto-restore when agent settles and editor is empty
  // -----------------------------------------------------------------------
  pi.on("agent_settled", async (_event, ctx) => {
    if (!stashed) return;

    const current = ctx.ui.getEditorText();
    if (!current || current.trim().length === 0) {
      ctx.ui.setEditorText(stashed);
      ctx.ui.setStatus("stash", undefined);
      ctx.ui.notify("📝 Stashed draft auto-restored", "info");
      stashed = null;
    }
  });

  // -----------------------------------------------------------------------
  // Command: /stash — show stash status
  // -----------------------------------------------------------------------
  pi.registerCommand("stash", {
    description: "Show stash status",
    handler: async (_args, ctx) => {
      if (stashed) {
        const preview = stashed.length > 100
          ? stashed.slice(0, 100) + "..."
          : stashed;
        ctx.ui.notify(`📝 Stashed (${stashed.length} chars):\n${preview}`, "info");
      } else {
        ctx.ui.notify("No stashed draft. Ctrl+S to stash your current input.", "info");
      }
    },
  });

  // -----------------------------------------------------------------------
  // Command: /stash-clear — discard stash without restoring
  // -----------------------------------------------------------------------
  pi.registerCommand("stash-clear", {
    description: "Discard stashed draft without restoring",
    handler: async (_args, ctx) => {
      if (stashed) {
        stashed = null;
        ctx.ui.setStatus("stash", undefined);
        ctx.ui.notify("📝 Stashed draft discarded", "info");
      } else {
        ctx.ui.notify("Nothing to clear", "info");
      }
    },
  });

  // -----------------------------------------------------------------------
  // Clear transient stash on session shutdown
  // -----------------------------------------------------------------------
  pi.on("session_shutdown", (_event) => {
    // Stash is cleared on shutdown — it's a transient UI state,
    // not meant to survive session restarts.
    stashed = null;
  });
}
