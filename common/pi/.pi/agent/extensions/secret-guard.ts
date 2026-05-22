// Secret Guard Extension for pi
// Blocks transmission of secrets, credentials, and sensitive data to external web tools.
// Implements 3-tier policy: allow / ask / deny.
//
// Install: place in ~/.pi/agent/extensions/secret-guard.ts

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";

// Patterns that indicate secrets/credentials
const SECRET_PATTERNS = [
  // API keys and tokens
  /(?:api[_-]?key|apikey)\s*[=:]\s*['"][^'"]{8,}['"]/i,
  /(?:secret|token|password|passwd|pwd)\s*[=:]\s*['"][^'"]{4,}['"]/i,
  /(?:aws_access_key_id|aws_secret_access_key)\s*[=:]/i,
  /(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{30,}/, // GitHub tokens
  /xox[baprs]-[A-Za-z0-9-]{10,}/, // Slack tokens
  /(?:sk|pk)-[A-Za-z0-9]{20,}/, // OpenAI-style keys
  /(?:AIza|AIzb)[A-Za-z0-9_-]{30,}/, // Google API keys

  // Private keys
  /-----BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY-----/,
  /-----BEGIN\s+OPENSSH\s+PRIVATE\s+KEY-----/,
  /-----BEGIN\s+EC\s+PRIVATE\s+KEY-----/,

  // .env file content
  /(?:DATABASE_URL|MONGO_URI|REDIS_URL|AUTH_SECRET)\s*=/,
  /(?:JWT_SECRET|SESSION_SECRET|ENCRYPTION_KEY)\s*=/,

  // Connection strings with credentials
  /(?:mongodb|postgres|mysql|redis):\/\/[^:]+:[^@]+@/i,

  // Customer/personal data markers
  /(?:customer[_-]data|user[_-]list|pii|gdpr)/i,
  /\b\d{3}-\d{2}-\d{4}\b/, // SSN pattern (US)
  /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/, // Credit card pattern
];

// File paths that should never be sent to web tools
const PROTECTED_PATHS = [
  /\.env(\..+)?$/,
  /\.aws\/credentials$/,
  /\.ssh\/(id_.+|authorized_keys)$/,
  /\.npmrc$/,
  /\.pypirc$/,
  /secrets\.(json|yaml|yml|toml)$/,
  /credentials\.(json|yaml|yml)$/,
  /\.gitconfig$/,
];

// Tier classification
type SecurityTier = "allow" | "ask" | "deny";

function classifyContent(content: string): { tier: SecurityTier; reason?: string } {
  // Check secret patterns
  for (const pattern of SECRET_PATTERNS) {
    if (pattern.test(content)) {
      return { tier: "deny", reason: `Secret pattern matched: ${pattern.source}` };
    }
  }

  // Check protected file paths
  for (const pattern of PROTECTED_PATHS) {
    if (pattern.test(content)) {
      return { tier: "deny", reason: `Protected file path: ${pattern.source}` };
    }
  }

  // Stack traces with file paths → ask tier
  if (/at\s+\S+\s+\(.+:\d+:\d+\)/.test(content) || /Traceback \(most recent call last\)/.test(content)) {
    return { tier: "ask", reason: "Stack trace detected — verify no secrets before sending" };
  }

  // Repository-specific internal URLs
  if (/(?:internal|corp|intranet|staging|dev-internal)/.test(content)) {
    return { tier: "ask", reason: "Internal URL or reference detected" };
  }

  return { tier: "allow" };
}

export default function (pi: ExtensionAPI) {
  // Intercept web_search and web_fetch tool calls
  pi.on("tool_call", async (event, ctx) => {
    const toolName = event.toolName;
    if (!toolName.startsWith("web_")) return;

    // Extract content to be sent
    const content = String(event.input?.query ?? event.input?.url ?? "");
    if (!content) return;

    const { tier, reason } = classifyContent(content);

    if (tier === "deny") {
      return {
        block: true,
        reason: `🔒 Secret Guard: ${reason}\n\nThis content appears to contain sensitive data and will not be sent to external web tools.`,
      };
    }

    if (tier === "ask") {
      const ok = await ctx.ui.confirm(
        "⚠️ Security Check",
        `This query may contain sensitive information.\n\n${reason}\n\nProceed with web search/fetch?`
      );
      if (!ok) {
        return { block: true, reason: "Blocked by secret-guard extension (user declined)" };
      }
    }
  });

  // Also intercept bash commands that read sensitive files before piping to web tools
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return;

    const command = String(event.input?.command ?? "");
    // Detect commands that read sensitive files and pipe to curl/fetch/wget
    if (/(?:cat|head|tail|grep)\s+.*\.env.*\|\s*(?:curl|fetch|wget|nc)/i.test(command)) {
      return {
        block: true,
        reason: "🔒 Secret Guard: Reading .env and piping to external tool is blocked.",
      };
    }
  });
}
