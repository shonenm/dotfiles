// Cap foreground bash timeouts so Cursor Grok/Composer cannot wait for hours.
// Cursor Shell defaults to timeout=30000s; Pi bash honors that value as seconds.
// Install: place in ~/.pi/agent/extensions/bash-timeout-cap.ts

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const BASH_TIMEOUT_CAP_SECONDS = 300;

// Tool names that execute shell commands. `bash` is pi's real tool; Cursor Shell
// is bridged onto it. The others are matched defensively.
const SHELL_TOOLS = new Set(["bash", "shell", "sh", "exec", "run"]);

export type TimeoutCapReason = "missing" | "invalid" | "over_cap" | "unchanged";

export interface TimeoutCap {
  timeout: number;
  reason: TimeoutCapReason;
  requested: unknown;
}

interface RecordedCap {
  reason: Exclude<TimeoutCapReason, "unchanged">;
  requested: unknown;
}

export function capBashTimeout(timeout: unknown): TimeoutCap {
  if (timeout === undefined || timeout === null) {
    return { timeout: BASH_TIMEOUT_CAP_SECONDS, reason: "missing", requested: timeout };
  }
  if (typeof timeout !== "number" || !Number.isFinite(timeout) || timeout <= 0) {
    return { timeout: BASH_TIMEOUT_CAP_SECONDS, reason: "invalid", requested: timeout };
  }
  if (timeout > BASH_TIMEOUT_CAP_SECONDS) {
    return { timeout: BASH_TIMEOUT_CAP_SECONDS, reason: "over_cap", requested: timeout };
  }
  return { timeout, reason: "unchanged", requested: timeout };
}

export function formatCapNote(cap: RecordedCap): string {
  const requested = formatRequested(cap.requested);
  return (
    `[bash-timeout-cap] Foreground bash timeout is capped at ${BASH_TIMEOUT_CAP_SECONDS}s ` +
    `(requested: ${requested}). Do not retry the same command with a longer timeout. ` +
    "Inspect the output, split the steps, or use MonitorCreate / pueue for work that needs more than 5 minutes."
  );
}

function formatRequested(requested: unknown): string {
  if (requested === undefined || requested === null) return "none";
  if (typeof requested === "number" && Number.isFinite(requested)) return `${requested}s`;
  return JSON.stringify(requested);
}

export default function (pi: ExtensionAPI) {
  const cappedCalls = new Map<string, RecordedCap>();

  pi.on("tool_call", (event) => {
    if (!SHELL_TOOLS.has(event.toolName)) return;
    if (!event.input || typeof event.input !== "object") return;

    const input = event.input as Record<string, unknown>;
    const capped = capBashTimeout(input.timeout);
    if (capped.reason === "unchanged") return;

    input.timeout = capped.timeout;
    cappedCalls.set(event.toolCallId, {
      reason: capped.reason,
      requested: capped.requested,
    });
  });

  pi.on("tool_result", (event) => {
    const cap = cappedCalls.get(event.toolCallId);
    if (!cap) return;
    cappedCalls.delete(event.toolCallId);

    const content = Array.isArray(event.content) ? [...event.content] : [];
    content.push({ type: "text", text: formatCapNote(cap) });
    return { content };
  });
}
