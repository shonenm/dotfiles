// Protected Paths Extension for pi
// Blocks writes/edits to sensitive files and directories.
// Install: place in ~/.pi/agent/extensions/protected-paths.ts

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Patterns are evaluated against the *path* string only (not the whole input
// JSON), so anchors like ^ and $ behave correctly. `(^|\/)` matches a basename
// segment so `project/.env` and `/home/u/.env` are caught, not just `.env`.
const PROTECTED_PATTERNS = [
  /(^|\/)\.env($|\.|\/)/,
  /(^|\/)\.git\//,
  /(^|\/)node_modules\//,
  /(^|\/)dist\//,
  /(^|\/)coverage\//,
  /(^|\/)\.next\//,
  /(^|\/)\.terraform\//,
  /id_rsa/,
  /id_ed25519/,
  /\.pem$/,
  /\.key$/,
  /\.p12$/,
  /\.pfx$/,
  /(^|\/)secrets?\.[^/]*$/i,
  /(^|\/)credentials?\.[^/]*$/i,
  /(^|\/)\.ssh\//,
  /(^|\/)\.aws\//,
  /(^|\/)\.docker\//,
];

// Extract candidate path strings from a tool input. Known path fields take
// precedence so we never test the file *content* (which would false-positive,
// e.g. a doc that merely mentions "secrets."). Falls back to scanning string
// values if no known field is present, so protection is not silently disabled
// when pi uses a different field name.
function candidatePaths(input: unknown): string[] {
  if (!input || typeof input !== "object") return [];
  const obj = input as Record<string, unknown>;
  const known = ["file_path", "filePath", "path", "filename", "file"];
  const found = known
    .map((k) => obj[k])
    .filter((v): v is string => typeof v === "string");
  if (found.length > 0) return found;
  return Object.values(obj).filter((v): v is string => typeof v === "string");
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (!["write", "edit"].includes(event.toolName)) return;

    for (const path of candidatePaths(event.input)) {
      const matched = PROTECTED_PATTERNS.find((p) => p.test(path));
      if (matched) {
        return {
          block: true,
          reason: `Protected path "${path}" (matched ${matched.source}). Ask the user explicitly before editing secrets, generated files, or dependency directories.`,
        };
      }
    }
  });
}
