// Protected Paths Extension for pi
// Blocks writes/edits to sensitive files and directories.
// Install: place in ~/.pi/agent/extensions/protected-paths.ts

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PROTECTED_PATTERNS = [
  /^\.env/,
  /^\.env\./,
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
  /secrets?\./i,
  /credentials?\./i,
  /(^|\/)\.ssh\//,
  /(^|\/)\.aws\//,
  /(^|\/)\.docker\//,
];

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (!["write", "edit"].includes(event.toolName)) return;

    const raw = JSON.stringify(event.input ?? {});
    const matched = PROTECTED_PATTERNS.find((p) => p.test(raw));

    if (matched) {
      return {
        block: true,
        reason: `Protected path: ${matched.source}. Ask the user explicitly before editing secrets, generated files, or dependency directories.`,
      };
    }
  });
}
