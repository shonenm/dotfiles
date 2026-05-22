// Citation Store Extension for pi
// Manages research citations and source lists.
// Provides tools for tracking what sources were used in answers.
//
// Install: place in ~/.pi/agent/extensions/citation-store.ts

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, appendFileSync, readFileSync, mkdirSync } from "node:fs";
import { ensureResearchDir } from "./audit-log.js";
import { homedir } from "node:os";
import { join } from "node:path";

const CITATIONS_FILE = join(process.env.HOME || homedir(), ".pi", "research", "citations.jsonl");

function ensureCitationsFile(): void {
  ensureResearchDir();
  if (!existsSync(CITATIONS_FILE)) {
    appendFileSync(CITATIONS_FILE, "");
  }
}

interface Citation {
  id: string;
  url: string;
  title: string;
  sourceType: string;
  fetchedAt: string;
  usedInAnswer: boolean;
  relevance: "primary" | "secondary" | "contradictory";
  tags: string[];
}

let citationCounter = 0;

function nextCitationId(): string {
  citationCounter++;
  return `[${citationCounter}]`;
}

function recordCitation(citation: Omit<Citation, "id" | "usedInAnswer">): Citation {
  ensureCitationsFile();
  const id = nextCitationId();
  const entry: Citation = { ...citation, id, usedInAnswer: false };
  appendFileSync(CITATIONS_FILE, JSON.stringify(entry) + "\n");
  return entry;
}

function getCitations(): Citation[] {
  ensureCitationsFile();
  if (!existsSync(CITATIONS_FILE)) return [];

  return readFileSync(CITATIONS_FILE, "utf-8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      try { return JSON.parse(line) as Citation; } catch { return null; }
    })
    .filter(Boolean) as Citation[];
}

function formatCitationList(citations: Citation[]): string {
  if (citations.length === 0) return "No citations recorded.";

  // Group by source type
  const byType: Record<string, Citation[]> = {};
  for (const c of citations) {
    const type = c.sourceType || "other";
    if (!byType[type]) byType[type] = [];
    byType[type].push(c);
  }

  const lines: string[] = ["## Research Sources", ""];

  for (const [type, items] of Object.entries(byType)) {
    lines.push(`### ${type}`);
    for (const c of items) {
      const marker = c.relevance === "primary" ? "✓" : c.relevance === "contradictory" ? "⚠" : "·";
      lines.push(`- ${c.id} ${marker} [${c.title || c.url}](${c.url}) (${c.fetchedAt.slice(0, 10)})`);
    }
    lines.push("");
  }

  return lines.join("\n");
}

function clearCitations(): void {
  ensureCitationsFile();
  appendFileSync(CITATIONS_FILE, "");
  citationCounter = 0;
}

// --- Tool Registration ---

export default function (pi: ExtensionAPI) {
  ensureResearchDir();

  pi.registerTool({
    name: "web_citation_add",
    description:
      "Record a source citation for the current research. Use after fetching to track what sources informed your answer.",
    parameters: {
      type: "object",
      properties: {
        url: { type: "string", description: "The source URL" },
        title: { type: "string", description: "Page title" },
        sourceType: { type: "string", description: "official_docs, github, blog, news, stackoverflow, etc." },
        relevance: { type: "string", enum: ["primary", "secondary", "contradictory"], description: "How relevant this source is" },
        tags: { type: "array", items: { type: "string" }, description: "Tags for categorization" },
      },
      required: ["url"],
    },
    async execute(input: { url: string; title?: string; sourceType?: string; relevance?: string; tags?: string[] }) {
      const citation = recordCitation({
        url: input.url,
        title: input.title || "",
        sourceType: input.sourceType || "other",
        fetchedAt: new Date().toISOString(),
        relevance: (input.relevance as Citation["relevance"]) || "secondary",
        tags: input.tags || [],
      });
      return { citationId: citation.id, url: citation.url };
    },
  });

  pi.registerTool({
    name: "web_citation_list",
    description: "List all citations recorded in the current research session.",
    parameters: {
      type: "object",
      properties: {},
    },
    async execute() {
      const citations = getCitations();
      return { citations: formatCitationList(citations), count: citations.length };
    },
  });

  pi.registerTool({
    name: "web_citation_clear",
    description: "Clear all citations for a new research session.",
    parameters: {
      type: "object",
      properties: {},
    },
    async execute() {
      clearCitations();
      return { cleared: true };
    },
  });
}
