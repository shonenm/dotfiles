// Web Router Extension for pi
// Routes search queries through multiple backends:
//   1. SearXNG (local, self-hosted) — no rate limits
//   2. DuckDuckGo HTML — free, no API key
//   3. Jina Search — requires JINA_API_KEY for higher limits
//
// Register tools:
//   web_search(query, domains?, recency?, max_results?)
//   web_search_docs(topic, version?)
//   web_search_github(query, repo?)

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { updateStats, ensureResearchDir, logAudit } from "./audit-log.js";

const SEARXNG_URL = process.env.SEARXNG_URL || "http://localhost:8888";
const MAX_CONTENT_LENGTH = 8000;

// --- SearXNG ---

async function searxngSearch(
  query: string,
  options: { maxResults?: number; domains?: string[]; recency?: string }
): Promise<string> {
  const params = new URLSearchParams({
    q: query,
    format: "json",
    categories: "general",
    language: "en",
    max_results: String(options.maxResults ?? 10),
  });

  // Domain restriction
  if (options.domains && options.domains.length > 0) {
    const siteQuery = options.domains.map((d) => `site:${d}`).join(" ") + " " + query;
    params.set("q", siteQuery);
  }

  // Time filter
  if (options.recency) {
    params.set("time_range", options.recency);
  }

  const url = `${SEARXNG_URL}/search?${params.toString()}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10000) });

  if (!res.ok) throw new Error(`SearXNG search failed: ${res.status}`);

  const data = await res.json() as { results: Array<{ title: string; url: string; content?: string; engine?: string }> };

  const lines = data.results.slice(0, options.maxResults ?? 10).map((r, i) => {
    return `[${i + 1}] ${r.title}\n    URL: ${r.url}\n    Source: ${r.engine || "unknown"}\n    ${r.content || ""}`;
  });

  return `SearXNG Results for "${query}"\n${"=".repeat(50)}\n${lines.join("\n\n")}`;
}

// --- DuckDuckGo HTML ---

async function duckduckgoSearch(
  query: string,
  options: { maxResults?: number }
): Promise<string> {
  const url = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
  const res = await fetch(url, {
    headers: { "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" },
    signal: AbortSignal.timeout(10000),
  });

  if (!res.ok) throw new Error(`DuckDuckGo search failed: ${res.status}`);

  const html = await res.text();

  // Parse results from HTML
  const results: Array<{ title: string; url: string; snippet: string }> = [];
  const resultRegex = /<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>.*?<a[^>]*class="result__snippet"[^>]*>(.*?)<\/a>/gs;
  let match;
  while ((match = resultRegex.exec(html)) !== null && results.length < (options.maxResults ?? 10)) {
    const url = match[1]!;
    const title = match[2]!.replace(/<[^>]*>/g, "").trim();
    const snippet = match[3]!.replace(/<[^>]*>/g, "").trim();
    if (url && title) {
      results.push({ title, url, snippet });
    }
  }

  if (results.length === 0) {
    // Fallback regex pattern
    const titleRegex = /class="result__a"[^>]*>(.*?)<\/a>/g;
    const urlRegex = /class="result__a"[^>]*href="([^"]*)"/g;
    const snippetRegex = /class="result__snippet"[^>]*>(.*?)<\/a>/g;

    const titles: string[] = [];
    const urls: string[] = [];
    const snippets: string[] = [];

    let m;
    while ((m = titleRegex.exec(html)) !== null) titles.push(m[1]!.replace(/<[^>]*>/g, "").trim());
    while ((m = urlRegex.exec(html)) !== null) urls.push(m[1]!);
    while ((m = snippetRegex.exec(html)) !== null) snippets.push(m[1]!.replace(/<[^>]*>/g, "").trim());

    for (let i = 0; i < Math.min(titles.length, urls.length, snippets.length, options.maxResults ?? 10); i++) {
      results.push({ title: titles[i]!, url: urls[i]!, snippet: snippets[i]! });
    }
  }

  const lines = results.map((r, i) => {
    return `[${i + 1}] ${r.title}\n    URL: ${r.url}\n    ${r.snippet}`;
  });

  return `DuckDuckGo Results for "${query}"\n${"=".repeat(50)}\n${lines.join("\n\n")}`;
}

// --- Jina Search ---

async function jinaSearch(query: string): Promise<string> {
  const apiKey = process.env.JINA_API_KEY;
  const headers: Record<string, string> = { Accept: "text/plain" };
  if (apiKey) headers["Authorization"] = `Bearer ${apiKey}`;

  const res = await fetch(`https://s.jina.ai/${encodeURIComponent(query)}`, {
    headers,
    signal: AbortSignal.timeout(10000),
  });

  if (!res.ok) throw new Error(`Jina search failed: ${res.status} ${res.statusText}`);

  let text = await res.text();
  if (text.length > MAX_CONTENT_LENGTH) {
    text = text.slice(0, MAX_CONTENT_LENGTH) + "\n... (truncated)";
  }
  return `Jina Search Results for "${query}"\n${"=".repeat(50)}\n${text}`;
}

// --- Search Router ---

async function search(
  query: string,
  options: { maxResults?: number; domains?: string[]; recency?: string } = {}
): Promise<{ content: string; provider: string }> {
  ensureResearchDir();

  // Try SearXNG first
  try {
    const content = await searxngSearch(query, options);
    logAudit({
      timestamp: new Date().toISOString(),
      tool: "web_search",
      query,
      status: "success",
      provider: "searxng",
      contentLength: content.length,
    });
    return { content, provider: "searxng" };
  } catch (err) {
    // SearXNG not available, continue to next
  }

  // Try DuckDuckGo
  try {
    const content = await duckduckgoSearch(query, options);
    logAudit({
      timestamp: new Date().toISOString(),
      tool: "web_search",
      query,
      status: "success",
      provider: "duckduckgo",
      contentLength: content.length,
    });
    return { content, provider: "duckduckgo" };
  } catch (err) {
    // DuckDuckGo failed, continue to next
  }

  // Try Jina (requires API key for reliability)
  if (process.env.JINA_API_KEY) {
    try {
      const content = await jinaSearch(query);
      logAudit({
        timestamp: new Date().toISOString(),
        tool: "web_search",
        query,
        status: "success",
        provider: "jina",
        contentLength: content.length,
      });
      return { content, provider: "jina" };
    } catch (err) {
      // Jina failed
    }
  }

  throw new Error(
    "All search backends failed.\n\n" +
    "1. Install SearXNG locally: docker compose -f services/docker-compose.searxng.yml up -d\n" +
    "2. Or set JINA_API_KEY for Jina Search\n" +
    "3. DuckDuckGo HTML scraping also failed — check network connectivity"
  );
}

// --- Tool Registration ---

export default function (pi: ExtensionAPI) {
  ensureResearchDir();

  pi.registerTool({
    name: "web_search",
    description:
      "Search the web using local SearXNG, DuckDuckGo, or Jina (fallback chain). Use for discovery only — always fetch source content before relying on it. " +
      "Parameters: query (required), domains (optional array to restrict search), recency (day/week/month), max_results (default 10).",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: "The search query" },
        domains: { type: "array", items: { type: "string" }, description: "Restrict to these domains (e.g., ['example.com'])" },
        recency: { type: "string", enum: ["day", "week", "month", "year"], description: "Time filter" },
        max_results: { type: "number", description: "Maximum results (default 10)" },
      },
      required: ["query"],
    },
    async execute(input: { query: string; domains?: string[]; recency?: string; max_results?: number }) {
      const { content, provider } = await search(input.query, {
        maxResults: input.max_results,
        domains: input.domains,
        recency: input.recency,
      });
      updateStats({ searchCount: (readStats().searchCount || 0) + 1 });
      return { content, provider };
    },
  });

  pi.registerTool({
    name: "web_search_docs",
    description:
      "Search specifically for documentation. Appends 'docs' or 'documentation' to the query. " +
      "Use for finding library, framework, or SDK documentation.",
    parameters: {
      type: "object",
      properties: {
        topic: { type: "string", description: "The topic to search docs for" },
        version: { type: "string", description: "Specific version (e.g., 'v15', '4.2')" },
      },
      required: ["topic"],
    },
    async execute(input: { topic: string; version?: string }) {
      const query = `${input.topic} documentation${input.version ? ` ${input.version}` : ""}`;
      const { content, provider } = await search(query, { domains: [], maxResults: 10 });
      updateStats({ searchCount: (readStats().searchCount || 0) + 1 });
      return { content, provider, query };
    },
  });

  pi.registerTool({
    name: "web_search_github",
    description:
      "Search GitHub for repositories, issues, or discussions. Restricts search to github.com.",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: "GitHub search query" },
        repo: { type: "string", description: "Specific repo (owner/repo) to search within" },
      },
      required: ["query"],
    },
    async execute(input: { query: string; repo?: string }) {
      const domains = ["github.com"];
      const fullQuery = input.repo ? `site:github.com/${input.repo} ${input.query}` : input.query;
      const { content, provider } = await search(fullQuery, { domains, maxResults: 10 });
      updateStats({ searchCount: (readStats().searchCount || 0) + 1 });
      return { content, provider, query: fullQuery };
    },
  });
}

function readStats(): { searchCount: number } {
  try {
    const { readFileSync } = require("node:fs");
    const { homedir } = require("node:os");
    const { join } = require("node:path");
    return JSON.parse(readFileSync(join(process.env.HOME || homedir(), ".pi", "research", "stats.json"), "utf-8"));
  } catch {
    return { searchCount: 0 };
  }
}
