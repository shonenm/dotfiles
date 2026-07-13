// Memory Extension for pi
//
// Persistent memory across sessions — pi-memory compatible format.
// Plain Markdown files as the storage layer, qmd for optional semantic search.
//
// Directory: ~/.pi/agent/memory/
//   MEMORY.md      — Curated long-term facts, decisions, preferences
//   SCRATCHPAD.md   — Checklist of things to fix/remember
//   daily/          — Daily append-only work logs
//
// Tools: memory_write, memory_read, memory_search, scratchpad
//
// Context injection (per pi-memory convention):
//   - Open scratchpad items (up to 2K chars)
//   - Today's daily log (up to 3K chars, tail)
//   - MEMORY.md (up to 4K chars)
//   Total injection capped at ~8K chars.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { existsSync, mkdirSync, readFileSync, writeFileSync, appendFileSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join, relative } from "node:path";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const MEMORY_DIR = join(homedir(), ".pi", "agent", "memory");
const MEMORY_FILE = join(MEMORY_DIR, "MEMORY.md");
const SCRATCHPAD_FILE = join(MEMORY_DIR, "SCRATCHPAD.md");
const DAILY_DIR = join(MEMORY_DIR, "daily");
// Pinned session note (set via /pin-goal). statusline.ts reads the same path.
const GOAL_FILE = join(homedir(), ".pi", "agent", "goal");

const INJECTION_MAX = 8000;
// Soft cap for MEMORY.md — beyond this, memory_write nudges the agent to curate.
// (Injection already only surfaces ~4KB, so unbounded growth wastes storage and
// dilutes relevance rather than helping.)
const MEMORY_SOFT_CAP = 50 * 1024;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function ensureDir(dir: string) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function todayStr(): string {
  return new Date().toISOString().slice(0, 10);
}

function dateStrDaysAgo(days: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}

function dailyFile(date?: string): string {
  return join(DAILY_DIR, `${date || todayStr()}.md`);
}

function readIfExists(path: string): string {
  if (!existsSync(path)) return "";
  try { return readFileSync(path, "utf-8"); } catch { return ""; }
}

function writeFile(path: string, content: string) {
  ensureDir(join(path, ".."));
  writeFileSync(path, content);
}

function appendFile(path: string, content: string) {
  ensureDir(join(path, ".."));
  appendFileSync(path, content);
}

// ---------------------------------------------------------------------------
// Scratchpad helpers
// ---------------------------------------------------------------------------

interface ScratchItem {
  done: boolean;
  text: string;
}

function parseScratchpad(): ScratchItem[] {
  const raw = readIfExists(SCRATCHPAD_FILE);
  return raw.split("\n")
    .filter((l) => l.startsWith("- [ ] ") || l.startsWith("- [x] "))
    .map((l) => ({ done: l.startsWith("- [x] "), text: l.slice(6) }));
}

function writeScratchpad(items: ScratchItem[]) {
  const lines = items.map((i) => `- [${i.done ? "x" : " "}] ${i.text}`);
  writeFile(SCRATCHPAD_FILE, lines.join("\n") + "\n");
}

// ---------------------------------------------------------------------------
// Context injection
// ---------------------------------------------------------------------------

function buildInjection(): string {
  const parts: string[] = [];
  let used = 0;

  // 0. Pinned session note (set via /pin-goal)
  const goal = readIfExists(GOAL_FILE).trim();
  if (goal) {
    const text = `## Current Goal\n${goal}`;
    parts.push(text.slice(0, 1000));
    used += Math.min(text.length, 1000);
  }

  // 1. Open scratchpad items
  const items = parseScratchpad().filter((i) => !i.done);
  if (items.length > 0) {
    const text = "## Scratchpad\n" + items.map((i) => `- [ ] ${i.text}`).join("\n");
    parts.push(text.slice(0, 2000));
    used += Math.min(text.length, 2000);
  }

  // 2. Today's daily log
  const daily = readIfExists(dailyFile());
  if (daily) {
    const lines = daily.split("\n");
    const tail = lines.slice(-60).join("\n"); // ~3K chars
    const budget = Math.min(tail.length, 3000, INJECTION_MAX - used);
    if (budget > 0) {
      parts.push(`## Today (${todayStr()})\n${tail.slice(-budget)}`);
      used += budget;
    }
  }

  // 2b. Yesterday's daily log (tail) — continuity across the day boundary
  if (used < INJECTION_MAX) {
    const yStr = dateStrDaysAgo(1);
    const yday = readIfExists(dailyFile(yStr));
    if (yday) {
      const tail = yday.split("\n").slice(-30).join("\n");
      const budget = Math.min(tail.length, 1500, INJECTION_MAX - used);
      if (budget > 0) {
        parts.push(`## Yesterday (${yStr})\n${tail.slice(-budget)}`);
        used += budget;
      }
    }
  }

  // 3. MEMORY.md (truncated from middle)
  if (used < INJECTION_MAX) {
    const mem = readIfExists(MEMORY_FILE);
    if (mem) {
      const budget = Math.min(mem.length, 4000, INJECTION_MAX - used);
      if (budget > 200) {
        if (mem.length <= budget) {
          parts.push(`## Memory\n${mem}`);
        } else {
          // Middle-truncate
          const half = Math.floor(budget / 2);
          const head = mem.slice(0, half);
          const tail = mem.slice(-half);
          parts.push(`## Memory\n${head}\n\n...\n\n${tail}`);
        }
      }
    }
  }

  return parts.join("\n\n");
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  ensureDir(DAILY_DIR);

  // -----------------------------------------------------------------------
  // Session start: inject memory context
  // -----------------------------------------------------------------------
  pi.on("session_start", async (_event, ctx) => {
    const injection = buildInjection();
    if (injection) {
      pi.sendMessage({
        customType: "memory-context",
        content: injection,
        display: false,
      }, { deliverAs: "nextTurn" });
    }

    const items = parseScratchpad();
    const openCount = items.filter((i) => !i.done).length;
    if (openCount > 0) {
      ctx.ui.notify(`Scratchpad: ${openCount} open items`, "info");
    }
  });

  // -----------------------------------------------------------------------
  // Session shutdown / compaction: handoff to daily log
  // -----------------------------------------------------------------------
  const writeHandoff = () => {
    const items = parseScratchpad().filter((i) => !i.done);
    if (items.length === 0) return;

    const now = new Date().toISOString();
    const lines = [
      `\n<!-- HANDOFF ${now} -->`,
      `## Session Handoff (${now.slice(0, 16)})`,
    ];
    lines.push("**Open scratchpad items:**");
    for (const item of items) {
      lines.push(`- [ ] ${item.text}`);
    }
    appendFile(dailyFile(), lines.join("\n") + "\n");
  };

  pi.on("session_shutdown", async () => writeHandoff());
  pi.on("session_before_compact", async () => writeHandoff());

  // -----------------------------------------------------------------------
  // Command: /pin-goal <text> | /pin-goal | /pin-goal clear
  // Pinned session note: injected as context (session start + on set) and shown
  // in the statusline (statusline.ts reads GOAL_FILE). `/goal` is reserved for
  // the pi-goal package.
  // -----------------------------------------------------------------------
  pi.registerCommand("pin-goal", {
    description: "Set/show/clear the pinned session note (injected as context + shown in statusline)",
    handler: async (args, ctx) => {
      const arg = (args || "").trim();
      if (!arg) {
        const g = readIfExists(GOAL_FILE).trim();
        ctx.ui.notify(g ? `🎯 Pinned: ${g}` : "No pinned note set. Usage: /pin-goal <text> (or /pin-goal clear)", "info");
        return;
      }
      if (arg === "clear") {
        writeFile(GOAL_FILE, "");
        ctx.ui.notify("Pinned note cleared", "info");
        return;
      }
      writeFile(GOAL_FILE, arg);
      // Inject now so the model sees the goal this turn, not only next session.
      pi.sendMessage(
        { customType: "goal", content: `## Current Goal\n${arg}`, display: false },
        { deliverAs: "nextTurn" }
      );
      ctx.ui.notify(`🎯 Pinned note set: ${arg}`, "info");
    },
  });

  // -----------------------------------------------------------------------
  // Tool: memory_write
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "memory_write",
    label: "Memory Write",
    description:
      "Write to long-term memory (MEMORY.md) or today's daily log. " +
      "Use target 'long_term' for facts/decisions/preferences you want to persist. " +
      "Use target 'daily' for work-in-progress notes.",
    promptSnippet: "Write to long-term memory or daily log",
    promptGuidelines: [
      "Use memory_write(target: 'long_term') for anything worth remembering across sessions.",
      "Use memory_write(target: 'daily') for temporary work notes.",
      "Use memory_read to recall what was previously stored.",
    ],
    parameters: Type.Object({
      content: Type.String({ description: "Content to write (Markdown)" }),
      target: Type.Optional(Type.String({ description: "'long_term' (MEMORY.md) or 'daily' (today's log). Default: 'long_term'" })),
    }),
    async execute(_toolCallId, params) {
      const target = params.target === "daily" ? "daily" : "long_term";
      const content = params.content;
      const timestamp = new Date().toISOString().slice(0, 16);

      if (target === "long_term") {
        const entry = `\n## ${timestamp}\n${content}\n`;
        appendFile(MEMORY_FILE, entry);
        const size = readIfExists(MEMORY_FILE).length;
        const hint = size > MEMORY_SOFT_CAP
          ? `\n\n⚠️ MEMORY.md is ${(size / 1024).toFixed(0)}KB (soft cap ${MEMORY_SOFT_CAP / 1024}KB). Consider curating stale entries — only ~4KB is injected at session start.`
          : "";
        return {
          content: [{ type: "text", text: `📝 Saved to MEMORY.md:\n\n${content.slice(0, 400)}${hint}` }],
          details: { target: "long_term", file: MEMORY_FILE, sizeBytes: size },
        };
      } else {
        const entry = `\n### ${timestamp}\n${content}\n`;
        appendFile(dailyFile(), entry);
        return {
          content: [{ type: "text", text: `📅 Added to daily log (${todayStr()}):\n\n${content.slice(0, 400)}` }],
          details: { target: "daily", file: dailyFile() },
        };
      }
    },
  });

  // -----------------------------------------------------------------------
  // Tool: memory_read
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "memory_read",
    label: "Memory Read",
    description:
      "Read memory files: MEMORY.md, today's daily log, or list all daily logs.",
    promptSnippet: "Read memory files or list daily logs",
    parameters: Type.Object({
      file: Type.Optional(Type.String({ description: "'mem' (MEMORY.md), 'daily' (today), or 'list' (all daily files). Default: 'mem'" })),
    }),
    async execute(_toolCallId, params) {
      const file = params.file || "mem";

      if (file === "list") {
        ensureDir(DAILY_DIR);
        const files = readdirSync(DAILY_DIR).filter((f) => f.endsWith(".md")).sort().reverse();
        const text = files.length === 0
          ? "No daily logs."
          : `## Daily Logs (${files.length})\n\n${files.map((f) => `- ${f.replace(".md", "")}`).join("\n")}`;
        return {
          content: [{ type: "text", text }],
          details: { type: "list", files },
        };
      }

      if (file === "daily") {
        const content = readIfExists(dailyFile());
        if (!content) {
          return {
            content: [{ type: "text", text: `No daily log for ${todayStr()}.` }],
            details: { type: "daily", empty: true },
          };
        }
        return {
          content: [{ type: "text", text: `## Daily Log: ${todayStr()}\n\n${content.slice(-8000)}` }],
          details: { type: "daily", date: todayStr(), length: content.length },
        };
      }

      // Default: MEMORY.md
      const content = readIfExists(MEMORY_FILE);
      if (!content) {
        return {
          content: [{ type: "text", text: "MEMORY.md is empty. Use memory_write to add long-term facts." }],
          details: { type: "mem", empty: true },
        };
      }
      return {
        content: [{ type: "text", text: `## MEMORY.md\n\n${content.slice(-10000)}` }],
        details: { type: "mem", length: content.length },
      };
    },
  });

  // -----------------------------------------------------------------------
  // Tool: memory_search
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "memory_search",
    label: "Memory Search",
    description:
      "Search across all memory files (MEMORY.md, daily logs) for keywords. " +
      "Matches file contents by substring. Install qmd for semantic/vector search.",
    promptSnippet: "Search memory files for keywords",
    parameters: Type.Object({
      query: Type.String({ description: "Search keywords" }),
    }),
    async execute(_toolCallId, params) {
      const query = params.query.toLowerCase();
      const results: Array<{ file: string; snippet: string }> = [];

      // Search MEMORY.md
      const mem = readIfExists(MEMORY_FILE);
      if (mem) {
        for (const line of mem.split("\n")) {
          if (line.toLowerCase().includes(query)) {
            results.push({ file: "MEMORY.md", snippet: line.trim().slice(0, 200) });
          }
        }
      }

      // Search all daily logs (newest first), not just today's
      ensureDir(DAILY_DIR);
      const dailyFiles = readdirSync(DAILY_DIR)
        .filter((f) => f.endsWith(".md"))
        .sort()
        .reverse();
      for (const f of dailyFiles) {
        const content = readIfExists(join(DAILY_DIR, f));
        for (const line of content.split("\n")) {
          if (line.toLowerCase().includes(query)) {
            results.push({ file: `daily/${f}`, snippet: line.trim().slice(0, 200) });
          }
        }
      }

      if (results.length === 0) {
        return {
          content: [{ type: "text", text: `No results for "${params.query}" in memory files.` }],
          details: { query: params.query, results: 0 },
        };
      }

      const text = results
        .slice(0, 20)
        .map((r) => `- **${r.file}**: ${r.snippet}`)
        .join("\n");

      return {
        content: [{
          type: "text",
          text: `## Search: "${params.query}" (${results.length} matches)\n\n${text.slice(0, 5000)}`,
        }],
        details: { query: params.query, totalMatches: results.length },
      };
    },
  });

  // -----------------------------------------------------------------------
  // Tool: scratchpad
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "scratchpad",
    label: "Scratchpad",
    description:
      "Manage a persistent checklist across sessions. " +
      "Actions: add (text), done (index), undo (index), clear, list. " +
      "Items persist in SCRATCHPAD.md and are injected on session start.",
    promptSnippet: "Manage persistent scratchpad checklist",
    parameters: Type.Object({
      action: Type.String({ description: "'add', 'done', 'undo', 'clear', or 'list'" }),
      text: Type.Optional(Type.String({ description: "Text for 'add' action" })),
      index: Type.Optional(Type.Number({ description: "1-based index for 'done'/'undo'" })),
    }),
    async execute(_toolCallId, params) {
      const items = parseScratchpad();

      switch (params.action) {
        case "add": {
          if (!params.text) {
            return { content: [{ type: "text", text: "Error: 'text' required for add" }], details: {} };
          }
          items.push({ done: false, text: params.text });
          writeScratchpad(items);
          return {
            content: [{ type: "text", text: `✓ Added #${items.length}: ${params.text}` }],
            details: { action: "add", total: items.length },
          };
        }
        case "done": {
          const i = (params.index || 1) - 1;
          if (i < 0 || i >= items.length) {
            return { content: [{ type: "text", text: `Invalid index: ${params.index}` }], details: {} };
          }
          items[i].done = true;
          writeScratchpad(items);
          const done = items.filter((x) => x.done).length;
          return {
            content: [{ type: "text", text: `✓ Done #${params.index}: ${items[i].text} (${done}/${items.length} completed)` }],
            details: { action: "done", index: params.index, done, total: items.length },
          };
        }
        case "undo": {
          const i = (params.index || 1) - 1;
          if (i < 0 || i >= items.length) {
            return { content: [{ type: "text", text: `Invalid index: ${params.index}` }], details: {} };
          }
          items[i].done = false;
          writeScratchpad(items);
          return {
            content: [{ type: "text", text: `↩ Undone #${params.index}: ${items[i].text}` }],
            details: { action: "undo", index: params.index },
          };
        }
        case "clear": {
          writeScratchpad([]);
          return {
            content: [{ type: "text", text: "✓ Cleared all scratchpad items." }],
            details: { action: "clear" },
          };
        }
        case "list":
        default: {
          if (items.length === 0) {
            return {
              content: [{ type: "text", text: "Scratchpad is empty." }],
              details: { action: "list", total: 0 },
            };
          }
          const text = items
            .map((it, idx) => `${it.done ? "☑" : "☐"} ${idx + 1}. ${it.text}`)
            .join("\n");
          const done = items.filter((x) => x.done).length;
          return {
            content: [{
              type: "text",
              text: `## Scratchpad (${done}/${items.length} done)\n\n${text}`,
            }],
            details: { action: "list", total: items.length, done },
          };
        }
      }
    },
  });
}
