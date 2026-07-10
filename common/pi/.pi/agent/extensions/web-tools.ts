// Web Research Tools Extension for pi
//
// Provides the web research toolchain:
//   web_search (SearXNG → Jina fallback)
//   web_fetch  (Jina Reader → raw curl fallback)
//   web_cache_lookup / web_cache_write
//   web_citation_add / web_citation_list
//
// Follows the protocol: search → fetch → cache → cite → answer
//
// Dependencies: SearXNG (docker), Jina AI (API key optional)

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync, appendFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { promises as dnsPromises } from "node:dns";
import { isIP } from "node:net";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const RESEARCH_DIR = join(homedir(), ".pi", "research");
const CACHE_DIR = join(RESEARCH_DIR, "sources");
const CITATIONS_FILE = join(RESEARCH_DIR, "citations.jsonl");
const AUDIT_FILE = join(RESEARCH_DIR, "audit.log.jsonl");
const STATS_FILE = join(RESEARCH_DIR, "stats.json");

const SEARXNG_URL = "http://localhost:8899";
const JINA_SEARCH_URL = "https://s.jina.ai";
const JINA_FETCH_URL = "https://r.jina.ai";

// Secret patterns to guard against leaking
const SECRET_PATTERNS = [
  /api[_-]?key[=:]\s*\S+/i,
  /token[=:]\s*\S+/i,
  /secret[=:]\s*\S+/i,
  /password[=:]\s*\S+/i,
  /-----BEGIN\s+(RSA|EC|OPENSSH|DSA)\s+PRIVATE KEY-----/,
  /sk-[a-zA-Z0-9]{20,}/,
  /xox[bprs]-[a-zA-Z0-9]{10,}/,
  /ghp_[a-zA-Z0-9]{36}/,
  /gho_[a-zA-Z0-9]{36}/,
  /ghu_[a-zA-Z0-9]{36}/,
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function ensureDir(dir: string) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function logAudit(action: string, detail: string, error?: string) {
  ensureDir(RESEARCH_DIR);
  const entry = {
    timestamp: new Date().toISOString(),
    action,
    detail: detail.slice(0, 500),
    error: error?.slice(0, 200) ?? null,
  };
  appendFileSync(AUDIT_FILE, JSON.stringify(entry) + "\n");
}

function updateStats(field: "searchCount" | "fetchCount" | "cacheHits" | "citationCount") {
  ensureDir(RESEARCH_DIR);
  let stats: Record<string, number> = {};
  if (existsSync(STATS_FILE)) {
    try { stats = JSON.parse(readFileSync(STATS_FILE, "utf-8")); } catch { /* reset */ }
  }
  stats[field] = (stats[field] ?? 0) + 1;
  writeFileSync(STATS_FILE, JSON.stringify(stats));
}

function urlHash(url: string): string {
  return createHash("sha256").update(url).digest("hex").slice(0, 16);
}

function checkSecrets(text: string): string | null {
  for (const p of SECRET_PATTERNS) {
    const m = text.match(p);
    if (m) return `Blocked: potential secret detected matching pattern: ${p.source}`;
  }
  return null;
}

// SSRF guard: reject URLs that resolve to internal / loopback / link-local
// addresses (e.g. the cloud metadata endpoint 169.254.169.254). All curl calls
// below pass arguments as an array (no shell), so command injection via the URL
// is not possible; this guard prevents the *destination* from being internal.
function isPrivateIp(ip: string): boolean {
  if (isIP(ip) === 4) {
    return (
      /^127\./.test(ip) ||
      /^10\./.test(ip) ||
      /^0\./.test(ip) ||
      /^169\.254\./.test(ip) ||
      /^192\.168\./.test(ip) ||
      /^172\.(1[6-9]|2\d|3[01])\./.test(ip)
    );
  }
  const v6 = ip.toLowerCase();
  return (
    v6 === "::1" ||
    v6 === "::" ||
    v6.startsWith("fe80") ||
    v6.startsWith("fc") ||
    v6.startsWith("fd") ||
    v6.startsWith("::ffff:127.") ||
    v6.startsWith("::ffff:10.") ||
    v6.startsWith("::ffff:192.168.") ||
    v6.startsWith("::ffff:169.254.")
  );
}

async function assertSafeUrl(rawUrl: string): Promise<string | null> {
  let host: string;
  let scheme: string;
  try {
    const u = new URL(rawUrl);
    host = u.hostname;
    scheme = u.protocol;
  } catch {
    return "Invalid URL";
  }
  if (scheme !== "http:" && scheme !== "https:") {
    return `Blocked: unsupported scheme "${scheme}"`;
  }
  if (!host) return "Blocked: empty host";

  // Literal IP in the URL
  if (isIP(host)) {
    return isPrivateIp(host) ? `Blocked: internal IP ${host}` : null;
  }

  // Resolve hostname and reject if any address is internal
  try {
    const addrs = await dnsPromises.lookup(host, { all: true });
    for (const a of addrs) {
      if (isPrivateIp(a.address)) {
        return `Blocked: ${host} resolves to internal address ${a.address}`;
      }
    }
  } catch {
    return `Blocked: cannot resolve host "${host}"`;
  }
  return null;
}

function curl(args: string[], opts: { timeout: number; maxBuffer?: number }): string | null {
  try {
    return execFileSync("curl", args, {
      encoding: "utf-8",
      timeout: opts.timeout,
      maxBuffer: opts.maxBuffer,
      stdio: ["pipe", "pipe", "pipe"],
    });
  } catch {
    return null;
  }
}

function searxngSearch(query: string, num: number): string | null {
  const url = `${SEARXNG_URL}/search?q=${encodeURIComponent(query)}&format=json`;
  const result = curl(["-fsSL", "--max-time", "15", url], { timeout: 16000 });
  if (!result) return null;
  try {
    const data = JSON.parse(result);
    if (!data.results || data.results.length === 0) return null;
    return JSON.stringify(data.results.slice(0, num), null, 2);
  } catch {
    return null;
  }
}

function jinaSearch(query: string): string | null {
  const apiKey = process.env.JINA_API_KEY;
  const args = ["-fsSL", "--max-time", "20"];
  if (apiKey) args.push("-H", `Authorization: Bearer ${apiKey}`);
  args.push(`${JINA_SEARCH_URL}/${encodeURIComponent(query)}`);
  const result = curl(args, { timeout: 21000 });
  return result ? result.slice(0, 8000) : null;
}

function jinaFetch(url: string): string | null {
  const apiKey = process.env.JINA_API_KEY;
  const args = ["-fsSL", "--max-time", "30"];
  if (apiKey) args.push("-H", `Authorization: Bearer ${apiKey}`);
  // X-Return-Format: markdown for clean output. The target is concatenated onto
  // the Jina prefix so it is a single argument starting with https (not a flag).
  args.push("-H", "X-Return-Format: markdown", `${JINA_FETCH_URL}/${url}`);
  const result = curl(args, { timeout: 31000, maxBuffer: 500 * 1024 });
  return result ? result.slice(0, 20000) : null;
}

function rawFetch(url: string): string | null {
  // `--` stops option parsing so a URL starting with `-` can't inject a flag.
  // Redirects are capped; note that a redirect *target* is not re-validated for
  // SSRF (residual risk), but the initial host is checked by assertSafeUrl.
  const result = curl(
    ["-fsSL", "--max-time", "15", "-L", "--max-redirs", "3", "--", url],
    { timeout: 16000, maxBuffer: 200 * 1024 }
  );
  return result ? result.slice(0, 10000) : null;
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  ensureDir(CACHE_DIR);

  // -----------------------------------------------------------------------
  // Tool: web_search
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description:
      "Search the web for information. Uses local SearXNG first (no rate limits, private), " +
      "falls back to Jina AI Search. Never rely on snippets alone; use web_fetch to retrieve full content.",
    promptSnippet: "Search the web for information (SearXNG → Jina fallback)",
    promptGuidelines: [
      "Use web_search for discovery only — never rely on snippets alone. Always fetch source content with web_fetch.",
      "Use web_cache_lookup before web_fetch to avoid redundant requests.",
    ],
    parameters: Type.Object({
      query: Type.String({ description: "Search query string" }),
      num: Type.Optional(Type.Number({ description: "Number of results (max 10, default 5)", default: 5 })),
    }),
    async execute(_toolCallId, params, _signal, onUpdate) {
      const { query, num = 5 } = params;
      const n = Math.min(Math.max(num, 1), 10);
      const trimmedQuery = query.trim().slice(0, 500);

      // Secret guard
      const secretErr = checkSecrets(trimmedQuery);
      if (secretErr) {
        logAudit("web_search_blocked", trimmedQuery, secretErr);
        return {
          content: [{ type: "text", text: `❌ ${secretErr}` }],
          details: { blocked: true, query: trimmedQuery.slice(0, 100) },
        };
      }

      onUpdate?.({ content: [{ type: "text", text: `🔍 Searching: ${trimmedQuery.slice(0, 100)}...` }] });

      // Try SearXNG first
      let result = searxngSearch(trimmedQuery, n);
      let backend = "searxng";

      if (!result) {
        onUpdate?.({ content: [{ type: "text", text: "SearXNG unavailable, trying Jina AI Search..." }] });
        result = jinaSearch(trimmedQuery);
        backend = "jina";
      }

      if (!result) {
        const msg = "All search backends failed (SearXNG not running, Jina AI unavailable). Start SearXNG: `docker compose -f ~/dotfiles/common/pi/services/docker-compose.searxng.yml up -d` or set JINA_API_KEY.";
        logAudit("web_search_failed", trimmedQuery, msg);
        return {
          content: [{ type: "text", text: `❌ ${msg}` }],
          details: { error: msg, query: trimmedQuery.slice(0, 100) },
        };
      }

      updateStats("searchCount");
      logAudit("web_search", `${backend}: ${trimmedQuery.slice(0, 100)}`);

      return {
        content: [{ type: "text", text: `## Search Results (via ${backend})\n\n${result.slice(0, 15000)}` }],
        details: { backend, query: trimmedQuery.slice(0, 100), resultCount: (result.match(/"url"/g) || []).length },
      };
    },
  });

  // -----------------------------------------------------------------------
  // Tool: web_fetch
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "web_fetch",
    label: "Web Fetch",
    description:
      "Fetch and convert a web page to clean markdown. Uses Jina Reader first (best quality), " +
      "falls back to raw HTTP fetch. Always check cache with web_cache_lookup before fetching.",
    promptSnippet: "Fetch a URL and convert to clean markdown (Jina Reader → raw fallback)",
    promptGuidelines: [
      "Use web_cache_lookup before web_fetch to avoid redundant requests.",
      "Use web_cache_write after web_fetch to cache the result.",
      "Use web_citation_add for every fetched source.",
    ],
    parameters: Type.Object({
      url: Type.String({ description: "URL to fetch" }),
    }),
    async execute(_toolCallId, params, _signal, onUpdate) {
      const url = params.url.trim();

      // Basic URL validation
      if (!url.startsWith("http://") && !url.startsWith("https://")) {
        return {
          content: [{ type: "text", text: "❌ Invalid URL. Must start with http:// or https://" }],
          details: { error: "invalid_url", url },
        };
      }

      // Secret guard
      const secretErr = checkSecrets(url);
      if (secretErr) {
        logAudit("web_fetch_blocked", url, secretErr);
        return {
          content: [{ type: "text", text: `❌ ${secretErr}` }],
          details: { blocked: true, url: url.slice(0, 100) },
        };
      }

      // SSRF guard — reject internal/loopback/link-local destinations
      const ssrfErr = await assertSafeUrl(url);
      if (ssrfErr) {
        logAudit("web_fetch_blocked", url, ssrfErr);
        return {
          content: [{ type: "text", text: `❌ ${ssrfErr}` }],
          details: { blocked: true, url: url.slice(0, 100) },
        };
      }

      onUpdate?.({ content: [{ type: "text", text: `📥 Fetching: ${url.slice(0, 80)}...` }] });

      // Try Jina Reader first
      let content = jinaFetch(url);
      let backend = "jina";

      if (!content) {
        onUpdate?.({ content: [{ type: "text", text: "Jina Reader unavailable, trying raw fetch..." }] });
        content = rawFetch(url);
        backend = "raw";
      }

      if (!content) {
        const msg = `Failed to fetch URL: ${url}. The site may be down, blocked, or require authentication.`;
        logAudit("web_fetch_failed", url, msg);
        return {
          content: [{ type: "text", text: `❌ ${msg}` }],
          details: { error: msg, url: url.slice(0, 100) },
        };
      }

      // Auto-cache
      const cacheFile = join(CACHE_DIR, `${urlHash(url)}.md`);
      try {
        const cacheEntry = `# ${url}\n## Fetched: ${new Date().toISOString()}\n## Backend: ${backend}\n\n${content}`;
        writeFileSync(cacheFile, cacheEntry);
      } catch { /* cache write failure is non-fatal */ }

      updateStats("fetchCount");
      logAudit("web_fetch", `${backend}: ${url.slice(0, 100)}`);

      return {
        content: [{ type: "text", text: content.slice(0, 20000) }],
        details: {
          backend,
          url: url.slice(0, 200),
          cached: cacheFile,
          contentLength: content.length,
        },
      };
    },
  });

  // -----------------------------------------------------------------------
  // Tool: web_cache_lookup
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "web_cache_lookup",
    label: "Web Cache Lookup",
    description: "Check if a URL has been previously fetched and cached. Returns cached content if available.",
    promptSnippet: "Look up a URL in the local web cache",
    promptGuidelines: ["Always check web_cache_lookup before web_fetch to avoid redundant requests."],
    parameters: Type.Object({
      url: Type.String({ description: "URL to look up in cache" }),
    }),
    async execute(_toolCallId, params, _signal) {
      const url = params.url.trim();
      const cacheFile = join(CACHE_DIR, `${urlHash(url)}.md`);

      if (!existsSync(cacheFile)) {
        return {
          content: [{ type: "text", text: `Cache miss: "${url.slice(0, 100)}" not in cache.` }],
          details: { cached: false, url: url.slice(0, 200) },
        };
      }

      const stat = statSync(cacheFile);
      const ageHours = (Date.now() - stat.mtimeMs) / (1000 * 60 * 60);
      const content = readFileSync(cacheFile, "utf-8").slice(0, 15000);

      updateStats("cacheHits");

      return {
        content: [{
          type: "text",
          text: `## Cached (${ageHours.toFixed(1)}h ago)\n\n${content}`,
        }],
        details: { cached: true, url: url.slice(0, 200), ageHours: Math.round(ageHours) },
      };
    },
  });

  // -----------------------------------------------------------------------
  // Tool: web_cache_write
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "web_cache_write",
    label: "Web Cache Write",
    description: "Store fetched content in the local cache for future lookup.",
    promptSnippet: "Store content in the local web cache",
    promptGuidelines: ["Cache everything useful with web_cache_write for future reference."],
    parameters: Type.Object({
      url: Type.String({ description: "Source URL" }),
      content: Type.String({ description: "Content to cache" }),
    }),
    async execute(_toolCallId, params, _signal) {
      const { url, content } = params;
      const cacheFile = join(CACHE_DIR, `${urlHash(url)}.md`);

      const cacheEntry = `# ${url}\n## Cached: ${new Date().toISOString()}\n\n${content.slice(0, 50000)}`;
      writeFileSync(cacheFile, cacheEntry);

      updateStats("cacheHits");

      return {
        content: [{ type: "text", text: `✅ Cached: ${url.slice(0, 100)}` }],
        details: { url: url.slice(0, 200), file: cacheFile },
      };
    },
  });

  // -----------------------------------------------------------------------
  // Tool: web_citation_add
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "web_citation_add",
    label: "Web Citation Add",
    description: "Add a source citation for the current research. Use for every source that informs your answer.",
    promptSnippet: "Record a source citation for research tracking",
    promptGuidelines: ["Use web_citation_add for every source that informed your answer."],
    parameters: Type.Object({
      url: Type.String({ description: "Source URL" }),
      title: Type.String({ description: "Source title" }),
      note: Type.Optional(Type.String({ description: "Optional note about this source" })),
    }),
    async execute(_toolCallId, params, _signal) {
      ensureDir(RESEARCH_DIR);
      const entry = {
        timestamp: new Date().toISOString(),
        url: params.url,
        title: params.title,
        note: params.note ?? null,
      };
      appendFileSync(CITATIONS_FILE, JSON.stringify(entry) + "\n");

      updateStats("citationCount");

      return {
        content: [{ type: "text", text: `📎 Cited: ${params.title.slice(0, 100)}` }],
        details: entry,
      };
    },
  });

  // -----------------------------------------------------------------------
  // Tool: web_citation_list
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "web_citation_list",
    label: "Web Citation List",
    description: "List all citations collected during the current research session.",
    promptSnippet: "List all collected source citations",
    parameters: Type.Object({}),
    async execute(_toolCallId, _params, _signal) {
      if (!existsSync(CITATIONS_FILE)) {
        return {
          content: [{ type: "text", text: "No citations recorded yet." }],
          details: { citations: [] },
        };
      }

      const lines = readFileSync(CITATIONS_FILE, "utf-8").trim().split("\n").filter(Boolean);
      const citations = lines.map((l) => JSON.parse(l));

      const text = citations.length === 0
        ? "No citations recorded."
        : `## Citations (${citations.length})\n\n` +
          citations.map((c, i) => `${i + 1}. [${c.title}](${c.url})${c.note ? ` — ${c.note}` : ""}`).join("\n");

      return {
        content: [{ type: "text", text }],
        details: { count: citations.length, citations },
      };
    },
  });

  // -----------------------------------------------------------------------
  // Notify on startup
  // -----------------------------------------------------------------------
  pi.on("session_start", async (_event, ctx) => {
    const searxngUp = searxngSearch("test", 1) !== null;
    const jinaKeySet = !!process.env.JINA_API_KEY;
    const parts: string[] = [];
    if (searxngUp) parts.push("SearXNG✅");
    else parts.push("SearXNG❌");
    if (jinaKeySet) parts.push("Jina✅");
    else parts.push("Jina❌(search-only)");
    ctx.ui.notify(`Web tools: ${parts.join(" ")}`, "info");
  });
}
