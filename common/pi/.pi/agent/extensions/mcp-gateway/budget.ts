import { randomUUID } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface BudgetResult {
  text: string;
  truncated: boolean;
  resultLength: number;
  overflowPath?: string;
}

const defaultOverflowDir = join(homedir(), ".pi", "research", "mcp-overflow");

const HINT =
  "Need a field not in this summary? Read the overflow file. Do not treat this as a complete dump.";

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function displayPath(path: string): string {
  return path.replace(homedir(), "~");
}

export function jsonInventory(text: string): Record<string, unknown> | undefined {
  try {
    const parsed: unknown = JSON.parse(text);
    if (Array.isArray(parsed)) {
      return {
        type: "array",
        length: parsed.length,
        itemBytes: parsed.map((item) => Buffer.byteLength(JSON.stringify(item), "utf8")),
      };
    }
    if (isRecord(parsed)) {
      return {
        type: "object",
        keys: Object.fromEntries(
          Object.entries(parsed).map(([key, value]) => [
            key,
            Buffer.byteLength(JSON.stringify(value), "utf8"),
          ]),
        ),
        bytes: Buffer.byteLength(text, "utf8"),
      };
    }
  } catch {
    // not JSON
  }
  return undefined;
}

function stringifyIfFits(value: unknown, maxSize: number): string | undefined {
  const text = JSON.stringify(value);
  return text.length <= maxSize ? text : undefined;
}

function fitEnvelope(
  metadata: Record<string, unknown>,
  shaped: string,
  original: string,
  maxSize: number,
): string {
  try {
    const parsed: unknown = JSON.parse(shaped);
    if (isRecord(parsed)) {
      const merged = stringifyIfFits({ ...parsed, ...metadata }, maxSize);
      if (merged) return merged;
    }
  } catch {
    // shaped body is not a JSON object
  }

  const inventory = jsonInventory(original);
  if (inventory) {
    const compact = stringifyIfFits({ ...inventory, ...metadata }, maxSize);
    if (compact) return compact;
  }

  return JSON.stringify(metadata);
}

export function applyResultBudget(
  text: string,
  maxSize: number,
  options: { originalText?: string; overflowDir?: string; omitted?: boolean } = {},
): BudgetResult {
  const original = options.originalText ?? text;
  const needsOverflow = Boolean(options.omitted) || text.length > maxSize;
  if (!needsOverflow) {
    return { text, truncated: false, resultLength: text.length };
  }

  const overflowDir = options.overflowDir ?? defaultOverflowDir;
  mkdirSync(overflowDir, { recursive: true });
  const overflowPath = join(overflowDir, `${Date.now()}-${randomUUID()}.json`);
  writeFileSync(overflowPath, original, "utf8");

  const metadata = {
    truncated: true,
    bytes: Buffer.byteLength(original, "utf8"),
    overflow: displayPath(overflowPath),
    hint: HINT,
  };

  return {
    text: fitEnvelope(metadata, text, original, maxSize),
    truncated: true,
    resultLength: original.length,
    overflowPath: displayPath(overflowPath),
  };
}
