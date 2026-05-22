// Web Fetch Extension for pi
// Fetches URL content with fallback chain:
//   1. Jina Reader — clean markdown extraction
//   2. Raw fetch + HTML text extraction (built-in)
//   3. Playwright (if available, for JS-heavy pages)
//
// Register tools:
//   web_fetch(url)
//   web_fetch_many(urls[])
//   web_extract_pdf(url_or_path)
//   web_crawl_site(url, max_pages?)

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { updateStats, ensureResearchDir, logAudit } from "./audit-log.js";

const MAX_CONTENT_LENGTH = 8000;

// --- Jina Reader ---

async function jinaFetch(url: string): Promise<string> {
  const apiKey = process.env.JINA_API_KEY;
  const headers: Record<string, string> = {
    Accept: "text/plain",
    "X-With-Generated-Alt": "true", // Better image descriptions
  };
  if (apiKey) {
    headers["Authorization"] = `Bearer ${apiKey}`;
  }

  const res = await fetch(`https://r.jina.ai/${encodeURIComponent(url)}`, {
    headers,
    signal: AbortSignal.timeout(15000),
  });

  if (!res.ok) throw new Error(`Jina fetch failed: ${res.status} ${res.statusText}`);

  return await res.text();
}

// --- Raw Fetch + HTML Text Extraction ---

function stripHtml(html: string): string {
  // Remove scripts, styles, comments
  let text = html
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();

  // Re-add some structure for headings
  const headingRegex = /<h[1-6][^>]*>(.*?)<\/h[1-6]>/gi;
  let match;
  while ((match = headingRegex.exec(html)) !== null) {
    const headingText = match[1]!.replace(/<[^>]+>/g, "").trim();
    text = text.replace(headingText, `\n## ${headingText}\n`);
  }

  return text;
}

async function rawFetch(url: string): Promise<string> {
  const res = await fetch(url, {
    headers: {
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
      Accept: "text/html,application/xhtml+xml",
    },
    signal: AbortSignal.timeout(15000),
  });

  if (!res.ok) throw new Error(`Raw fetch failed: ${res.status} ${res.statusText}`);

  const contentType = res.headers.get("content-type") || "";
  if (contentType.includes("json")) {
    const text = await res.text();
    try {
      const parsed = JSON.parse(text);
      return JSON.stringify(parsed, null, 2);
    } catch {
      return text;
    }
  }

  const html = await res.text();
  return stripHtml(html);
}

// --- Playwright Fallback ---

async function playwrightFetch(url: string): Promise<string> {
  // Check if npx playwright is available
  try {
    execSync("npx playwright --version", { stdio: "ignore", timeout: 5000 });
  } catch {
    throw new Error("Playwright not available");
  }

  // Use Playwright to render the page
  const script = `
    const { chromium } = require('playwright');
    (async () => {
      const browser = await chromium.launch({ headless: true });
      const page = await browser.newPage();
      await page.goto('${url.replace(/'/g, "\\'")}', { waitUntil: 'networkidle', timeout: 15000 });
      const text = await page.evaluate(() => document.body.innerText);
      await browser.close();
      console.log(text);
    })();
  `;

  const result = execSync(`node -e "${script.replace(/\n/g, " ")}"`, {
    encoding: "utf-8",
    timeout: 20000,
  });

  return result.trim();
}

// --- Fetch Router ---

async function fetchUrl(url: string): Promise<{ content: string; provider: string }> {
  ensureResearchDir();

  // Try Jina first
  try {
    const content = await jinaFetch(url);
    const truncated = content.length > MAX_CONTENT_LENGTH
      ? content.slice(0, MAX_CONTENT_LENGTH) + "\n... (truncated)"
      : content;
    logAudit({
      timestamp: new Date().toISOString(),
      tool: "web_fetch",
      url,
      status: "success",
      provider: "jina",
      contentLength: truncated.length,
    });
    return { content: truncated, provider: "jina" };
  } catch {
    // Jina failed, continue
  }

  // Try Playwright (for JS-heavy pages)
  try {
    const content = await playwrightFetch(url);
    const truncated = content.length > MAX_CONTENT_LENGTH
      ? content.slice(0, MAX_CONTENT_LENGTH) + "\n... (truncated)"
      : content;
    logAudit({
      timestamp: new Date().toISOString(),
      tool: "web_fetch",
      url,
      status: "success",
      provider: "playwright",
      contentLength: truncated.length,
    });
    return { content: truncated, provider: "playwright" };
  } catch {
    // Playwright failed or not available, continue
  }

  // Raw fetch fallback
  try {
    const content = await rawFetch(url);
    const truncated = content.length > MAX_CONTENT_LENGTH
      ? content.slice(0, MAX_CONTENT_LENGTH) + "\n... (truncated)"
      : content;
    logAudit({
      timestamp: new Date().toISOString(),
      tool: "web_fetch",
      url,
      status: "success",
      provider: "raw",
      contentLength: truncated.length,
    });
    return { content: truncated, provider: "raw" };
  } catch (err) {
    throw new Error(`All fetch backends failed for ${url}: ${(err as Error).message}`);
  }
}

// --- PDF Extraction ---

function extractPdf(urlOrPath: string): string {
  // Try pdftotext (poppler-utils)
  try {
    execSync("pdftotext -v", { stdio: "ignore" });
    const tmpFile = `/tmp/pdf_${Date.now()}.txt`;
    let pdfPath = urlOrPath;

    // If it's a URL, download first
    if (urlOrPath.startsWith("http")) {
      const tmpPdf = `/tmp/pdf_${Date.now()}.pdf`;
      execSync(`curl -fsSL --max-time 30 '${urlOrPath}' -o '${tmpPdf}'`);
      pdfPath = tmpPdf;
    }

    execSync(`pdftotext -layout '${pdfPath}' '${tmpFile}'`, { timeout: 30000 });
    const text = readFileSync(tmpFile, "utf-8");
    execSync(`rm -f '${tmpFile}' '${pdfPath}'`);
    return text.slice(0, MAX_CONTENT_LENGTH);
  } catch {
    return "pdftotext not available. Install poppler-utils for PDF extraction.";
  }
}

// --- Tool Registration ---

export default function (pi: ExtensionAPI) {
  ensureResearchDir();

  pi.registerTool({
    name: "web_fetch",
    description:
      "Fetch and extract clean content from a URL. Tries Jina Reader → Playwright → Raw fetch. " +
      "Always check web_cache_lookup first to avoid redundant requests.",
    parameters: {
      type: "object",
      properties: {
        url: { type: "string", description: "The URL to fetch" },
      },
      required: ["url"],
    },
    async execute(input: { url: string }) {
      const { content, provider } = await fetchUrl(input.url);
      updateStats({ fetchCount: (readStats().fetchCount || 0) + 1 });
      return { content, provider, url: input.url };
    },
  });

  pi.registerTool({
    name: "web_fetch_many",
    description:
      "Fetch multiple URLs in parallel. Returns array of results. Use for comparing documentation across versions.",
    parameters: {
      type: "object",
      properties: {
        urls: { type: "array", items: { type: "string" }, description: "URLs to fetch" },
      },
      required: ["urls"],
    },
    async execute(input: { urls: string[] }) {
      const results = await Promise.allSettled(
        input.urls.map(async (url) => {
          const { content, provider } = await fetchUrl(url);
          updateStats({ fetchCount: (readStats().fetchCount || 0) + 1 });
          return { url, content, provider, status: "success" as const };
        })
      );

      return results.map((r, i) => {
        if (r.status === "fulfilled") return r.value;
        return { url: input.urls[i], status: "error", error: r.reason };
      });
    },
  });

  pi.registerTool({
    name: "web_extract_pdf",
    description:
      "Extract text from a PDF file (URL or local path). Requires pdftotext (poppler-utils).",
    parameters: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL or local path to PDF" },
      },
      required: ["url"],
    },
    async execute(input: { url: string }) {
      const content = extractPdf(input.url);
      return { content, url: input.url };
    },
  });
}

function readStats(): { fetchCount: number } {
  try {
    const { readFileSync } = require("node:fs");
    const { homedir } = require("node:os");
    const { join } = require("node:path");
    return JSON.parse(readFileSync(join(process.env.HOME || homedir(), ".pi", "research", "stats.json"), "utf-8"));
  } catch {
    return { fetchCount: 0 };
  }
}
