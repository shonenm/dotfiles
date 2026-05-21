// Web Tools Extension for pi
// Provides web_search and web_fetch tools via Jina AI.
// No API key required for low volume; set JINA_API_KEY for higher rate limits.
// Install: place in ~/.pi/agent/extensions/web-tools.ts

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const JINA_FETCH_URL = "https://r.jina.ai";
const JINA_SEARCH_URL = "https://s.jina.ai";
const MAX_CONTENT_LENGTH = 8000;

async function jinaFetch(url: string): Promise<string> {
  const apiKey = process.env.JINA_API_KEY;
  const headers: Record<string, string> = {
    Accept: "text/plain",
  };
  if (apiKey) {
    headers["Authorization"] = `Bearer ${apiKey}`;
  }

  const res = await fetch(`${JINA_FETCH_URL}/${encodeURIComponent(url)}`, {
    headers,
  });

  if (!res.ok) {
    throw new Error(`Jina fetch failed: ${res.status} ${res.statusText}`);
  }

  let text = await res.text();
  if (text.length > MAX_CONTENT_LENGTH) {
    text = text.slice(0, MAX_CONTENT_LENGTH) + "\n... (truncated)";
  }
  return text;
}

async function jinaSearch(query: string): Promise<string> {
  const apiKey = process.env.JINA_API_KEY;
  const headers: Record<string, string> = {
    Accept: "text/plain",
  };
  if (apiKey) {
    headers["Authorization"] = `Bearer ${apiKey}`;
  }

  const res = await fetch(`${JINA_SEARCH_URL}/${encodeURIComponent(query)}`, {
    headers,
  });

  if (!res.ok) {
    throw new Error(`Jina search failed: ${res.status} ${res.statusText}`);
  }

  let text = await res.text();
  if (text.length > MAX_CONTENT_LENGTH) {
    text = text.slice(0, MAX_CONTENT_LENGTH) + "\n... (truncated)";
  }
  return text;
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "web_fetch",
    description:
      "Fetch and extract clean markdown content from a URL. Use for documentation, articles, or any web page. Set JINA_API_KEY env var for higher rate limits.",
    parameters: {
      type: "object",
      properties: {
        url: {
          type: "string",
          description: "The URL to fetch",
        },
      },
      required: ["url"],
    },
    async execute(input: { url: string }) {
      const content = await jinaFetch(input.url);
      return { content };
    },
  });

  pi.registerTool({
    name: "web_search",
    description:
      "Search the web and return summarized results. Use for finding documentation, latest best practices, or factual information. Set JINA_API_KEY env var for higher rate limits.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "The search query",
        },
      },
      required: ["query"],
    },
    async execute(input: { query: string }) {
      const content = await jinaSearch(input.query);
      return { content };
    },
  });
}
