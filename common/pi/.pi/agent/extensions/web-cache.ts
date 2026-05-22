// Web Cache Extension for pi
// File-based cache for web research results.
// Stores sources under ~/.pi/research/sources/<hash>.md
// Stores metadata in ~/.pi/research/metadata.jsonl
//
// Cache policy:
// - Active library docs: 7 days
// - Stable specs: 30 days
// - News/current info: always refresh
// - GitHub repos: per commit hash

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  readdirSync,
  statSync,
  appendFileSync,
  unlinkSync,
} from "node:fs";
import { createHash } from "node:crypto";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { updateStats, ensureResearchDir, logAudit } from "./audit-log.js";

const SOURCES_DIR = join(process.env.HOME || homedir(), ".pi", "research", "sources");
const METADATA_FILE = join(process.env.HOME || homedir(), ".pi", "research", "metadata.jsonl");

// Cache TTL in milliseconds
const TTL: Record<string, number> = {
  official_docs: 7 * 24 * 60 * 60 * 1000, // 7 days
  github: 30 * 24 * 60 * 60 * 1000, // 30 days
  news: 0, // always refresh
  blog: 7 * 24 * 60 * 60 * 1000, // 7 days
  default: 7 * 24 * 60 * 60 * 1000, // 7 days
};

function ensureDirs(): void {
  ensureResearchDir();
  if (!existsSync(SOURCES_DIR)) mkdirSync(SOURCES_DIR, { recursive: true });
}

function hashUrl(url: string): string {
  return createHash("md5").update(url).digest("hex").slice(0, 16);
}

interface CacheMetadata {
  url: string;
  title: string;
  fetchedAt: string;
  provider: string;
  contentHash: string;
  sourceType: string;
  tags: string[];
  filePath: string;
}

function findCached(url: string): CacheMetadata | null {
  ensureDirs();
  if (!existsSync(METADATA_FILE)) return null;

  const lines = readFileSync(METADATA_FILE, "utf-8").trim().split("\n").filter(Boolean);

  // Search from newest to oldest
  for (let i = lines.length - 1; i >= 0; i--) {
    try {
      const entry: CacheMetadata = JSON.parse(lines[i]!);
      if (entry.url === url) {
        // Check TTL
        const ttl = TTL[entry.sourceType] ?? TTL.default;
        if (ttl === 0) return null; // always refresh

        const age = Date.now() - new Date(entry.fetchedAt).getTime();
        if (age < ttl) {
          updateStats({ cacheHits: (readStats().cacheHits || 0) + 1 });
          return entry;
        }
        return null; // expired
      }
    } catch {
      // skip malformed lines
    }
  }
  return null;
}

function readStats(): { cacheHits: number; cacheMisses: number } {
  try {
    return JSON.parse(readFileSync(join(process.env.HOME || homedir(), ".pi", "research", "stats.json"), "utf-8"));
  } catch {
    return { cacheHits: 0, cacheMisses: 0 };
  }
}

function saveContent(url: string, content: string, meta: Omit<CacheMetadata, "filePath" | "contentHash">): CacheMetadata {
  ensureDirs();

  const hash = hashUrl(url);
  const filePath = join(SOURCES_DIR, `${hash}.md`);
  const contentHash = createHash("sha256").update(content).digest("hex");

  writeFileSync(filePath, content);

  const entry: CacheMetadata = {
    ...meta,
    filePath,
    contentHash,
  };

  appendFileSync(METADATA_FILE, JSON.stringify(entry) + "\n");
  updateStats({ cacheMisses: (readStats().cacheMisses || 0) + 1 });

  logAudit({
    timestamp: new Date().toISOString(),
    tool: "web_cache_write",
    url,
    status: "success",
    provider: meta.provider,
    contentLength: content.length,
  });

  return entry;
}

function clearExpired(): number {
  ensureDirs();
  if (!existsSync(METADATA_FILE)) return 0;

  const lines = readFileSync(METADATA_FILE, "utf-8").trim().split("\n").filter(Boolean);
  let cleared = 0;

  const validLines: string[] = [];
  for (const line of lines) {
    try {
      const entry: CacheMetadata = JSON.parse(line);
      const ttl = TTL[entry.sourceType] ?? TTL.default;
      if (ttl > 0) {
        const age = Date.now() - new Date(entry.fetchedAt).getTime();
        if (age >= ttl && existsSync(entry.filePath)) {
          unlinkSync(entry.filePath);
          cleared++;
          continue;
        }
      }
      validLines.push(line);
    } catch {
      validLines.push(line);
    }
  }

  if (validLines.length !== lines.length) {
    writeFileSync(METADATA_FILE, validLines.join("\n") + "\n");
  }

  return cleared;
}

// Register tools
export default function (pi: ExtensionAPI) {
  ensureDirs();

  pi.registerTool({
    name: "web_cache_lookup",
    description:
      "Check if a URL's content is already cached locally. Returns cached content if available and not expired. Use before web_fetch to avoid redundant requests.",
    parameters: {
      type: "object",
      properties: {
        url: { type: "string", description: "The URL to look up in cache" },
      },
      required: ["url"],
    },
    async execute(input: { url: string }) {
      const cached = findCached(input.url);
      if (cached && existsSync(cached.filePath)) {
        const content = readFileSync(cached.filePath, "utf-8");
        return {
          content,
          cached: true,
          fetchedAt: cached.fetchedAt,
          provider: cached.provider,
          sourceType: cached.sourceType,
          filePath: cached.filePath,
        };
      }
      return { cached: false, url: input.url };
    },
  });

  pi.registerTool({
    name: "web_cache_write",
    description:
      "Save fetched content to the local research cache. Use after web_fetch to store results.",
    parameters: {
      type: "object",
      properties: {
        url: { type: "string", description: "The source URL" },
        content: { type: "string", description: "The content to cache (markdown)" },
        title: { type: "string", description: "Page title" },
        provider: { type: "string", description: "Fetch provider (jina, playwright, readability)" },
        sourceType: { type: "string", description: "Type: official_docs, github, news, blog, etc." },
        tags: { type: "array", items: { type: "string" }, description: "Tags for categorization" },
      },
      required: ["url", "content"],
    },
    async execute(input: { url: string; content: string; title?: string; provider?: string; sourceType?: string; tags?: string[] }) {
      const entry = saveContent(input.url, input.content, {
        url: input.url,
        title: input.title || "",
        fetchedAt: new Date().toISOString(),
        provider: input.provider || "manual",
        sourceType: input.sourceType || "default",
        tags: input.tags || [],
      });
      return { cached: true, filePath: entry.filePath, contentHash: entry.contentHash };
    },
  });

  pi.registerTool({
    name: "web_cache_clear",
    description: "Clear expired cache entries. Returns count of cleared entries.",
    parameters: {
      type: "object",
      properties: {
        all: { type: "boolean", description: "Clear all cache entries (default: only expired)" },
      },
    },
    async execute(input: { all?: boolean }) {
      if (input.all) {
        if (existsSync(SOURCES_DIR)) {
          const files = readdirSync(SOURCES_DIR);
          for (const f of files) {
            try { unlinkSync(join(SOURCES_DIR, f)); } catch { /* ignore */ }
          }
        }
        if (existsSync(METADATA_FILE)) writeFileSync(METADATA_FILE, "");
        return { cleared: "all" };
      }
      const cleared = clearExpired();
      return { cleared };
    },
  });
}
