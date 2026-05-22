// Audit Log Extension for pi
// Logs all web tool usage for transparency and debugging.
// Stores entries in ~/.pi/research/audit.log.jsonl
//
// Shared stats are read by statusline.ts for the footer display.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const RESEARCH_DIR = join(homedir(), ".pi", "research");
const AUDIT_LOG = join(RESEARCH_DIR, "audit.log.jsonl");
const STATS_FILE = join(RESEARCH_DIR, "stats.json");

export interface AuditEntry {
  timestamp: string;
  tool: string;
  query?: string;
  url?: string;
  status: "success" | "error" | "blocked";
  provider: string;
  contentLength?: number;
  durationMs?: number;
}

export interface ResearchStats {
  searchCount: number;
  fetchCount: number;
  cacheHits: number;
  cacheMisses: number;
  blockedCount: number;
  lastReset: string;
}

function ensureResearchDir(): void {
  if (!existsSync(RESEARCH_DIR)) {
    mkdirSync(RESEARCH_DIR, { recursive: true });
  }
  // .gitignore
  const gitignore = join(RESEARCH_DIR, ".gitignore");
  if (!existsSync(gitignore)) {
    writeFileSync(gitignore, "*\n!.gitignore\n");
  }
  // Initialize stats
  if (!existsSync(STATS_FILE)) {
    writeFileSync(
      STATS_FILE,
      JSON.stringify({
        searchCount: 0,
        fetchCount: 0,
        cacheHits: 0,
        cacheMisses: 0,
        blockedCount: 0,
        lastReset: new Date().toISOString(),
      } as ResearchStats, null, 2)
    );
  }
}

function logAudit(entry: AuditEntry): void {
  ensureResearchDir();
  appendFileSync(AUDIT_LOG, JSON.stringify(entry) + "\n");
}

function updateStats(updates: Partial<ResearchStats>): void {
  ensureResearchDir();
  let stats: ResearchStats;
  try {
    stats = JSON.parse(readFileSync(STATS_FILE, "utf-8"));
  } catch {
    stats = {
      searchCount: 0,
      fetchCount: 0,
      cacheHits: 0,
      cacheMisses: 0,
      blockedCount: 0,
      lastReset: new Date().toISOString(),
    };
  }
  Object.assign(stats, updates);
  writeFileSync(STATS_FILE, JSON.stringify(stats, null, 2));
}

export { ensureResearchDir, logAudit, updateStats, AUDIT_LOG, STATS_FILE, RESEARCH_DIR };

export default function (pi: ExtensionAPI) {
  ensureResearchDir();

  // Reset stats on new session
  pi.on("session_start", () => {
    updateStats({
      searchCount: 0,
      fetchCount: 0,
      cacheHits: 0,
      cacheMisses: 0,
      blockedCount: 0,
    });
  });

  // Log all tool calls related to web research
  pi.on("tool_call", async (event) => {
    const toolName = event.toolName;
    if (!toolName.startsWith("web_")) return;

    const entry: AuditEntry = {
      timestamp: new Date().toISOString(),
      tool: toolName,
      status: "success",
      provider: "unknown",
    };

    if (toolName.includes("search")) {
      entry.query = String(event.input?.query ?? "");
      updateStats({ searchCount: (JSON.parse(readFileSync(STATS_FILE, "utf-8")) as ResearchStats).searchCount + 1 });
    }
    if (toolName.includes("fetch")) {
      entry.url = String(event.input?.url ?? "");
      updateStats({ fetchCount: (JSON.parse(readFileSync(STATS_FILE, "utf-8")) as ResearchStats).fetchCount + 1 });
    }
    if (toolName.includes("cache")) {
      entry.query = String(event.input?.query ?? event.input?.url ?? "");
    }

    logAudit(entry);
  });
}
