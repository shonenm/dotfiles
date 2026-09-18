#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ln -s "$root/common/pi/.pi/agent/extensions/bash-timeout-cap.ts" "$tmp/bash-timeout-cap.ts"

cd "$tmp"
node --experimental-strip-types --preserve-symlinks --input-type=module - "$tmp" <<'JS'
import assert from "node:assert/strict";

const tmp = process.argv[2];
const {
  BASH_TIMEOUT_CAP_SECONDS,
  capBashTimeout,
  formatCapNote,
  default: register,
} = await import(`file://${tmp}/bash-timeout-cap.ts`);

assert.equal(BASH_TIMEOUT_CAP_SECONDS, 300);
assert.deepEqual(capBashTimeout(undefined), { timeout: 300, reason: "missing", requested: undefined });
assert.deepEqual(capBashTimeout(null), { timeout: 300, reason: "missing", requested: null });
assert.deepEqual(capBashTimeout(30000), { timeout: 300, reason: "over_cap", requested: 30000 });
assert.deepEqual(capBashTimeout(300.1), { timeout: 300, reason: "over_cap", requested: 300.1 });
assert.deepEqual(capBashTimeout(300), { timeout: 300, reason: "unchanged", requested: 300 });
assert.deepEqual(capBashTimeout(120), { timeout: 120, reason: "unchanged", requested: 120 });
assert.deepEqual(capBashTimeout(0), { timeout: 300, reason: "invalid", requested: 0 });
assert.deepEqual(capBashTimeout(-1), { timeout: 300, reason: "invalid", requested: -1 });
assert.equal(capBashTimeout(Number.NaN).reason, "invalid");
assert.equal(capBashTimeout(Number.POSITIVE_INFINITY).reason, "invalid");
assert.deepEqual(capBashTimeout("30000"), { timeout: 300, reason: "invalid", requested: "30000" });
assert.match(formatCapNote({ reason: "over_cap", requested: 30000 }), /300s \(requested: 30000s\)/);
assert.match(formatCapNote({ reason: "missing", requested: undefined }), /requested: none/);

const handlers = {};
register({
  on(name, fn) {
    handlers[name] = fn;
  },
});

const over = { command: "sleep 999", timeout: 30000 };
await handlers.tool_call({ toolName: "bash", toolCallId: "t-over", input: over });
assert.equal(over.timeout, 300);
const overResult = await handlers.tool_result({
  toolName: "bash",
  toolCallId: "t-over",
  input: over,
  content: [{ type: "text", text: "still running" }],
  isError: true,
});
assert.equal(overResult.content[0].text, "still running");
assert.match(overResult.content[1].text, /capped at 300s \(requested: 30000s\)/);
assert.match(overResult.content[1].text, /Do not retry the same command with a longer timeout/);

const missing = { command: "pnpm test" };
await handlers.tool_call({ toolName: "bash", toolCallId: "t-missing", input: missing });
assert.equal(missing.timeout, 300);
const missingResult = await handlers.tool_result({
  toolName: "bash",
  toolCallId: "t-missing",
  input: missing,
  content: [],
});
assert.match(missingResult.content[0].text, /requested: none/);

const kept = { command: "ls", timeout: 60 };
await handlers.tool_call({ toolName: "bash", toolCallId: "t-kept", input: kept });
assert.equal(kept.timeout, 60);
assert.equal(
  await handlers.tool_result({
    toolName: "bash",
    toolCallId: "t-kept",
    input: kept,
    content: [{ type: "text", text: "ok" }],
  }),
  undefined,
);

const other = { path: "README.md", timeout: 30000 };
await handlers.tool_call({ toolName: "read", toolCallId: "t-read", input: other });
assert.equal(other.timeout, 30000);
assert.equal(
  await handlers.tool_result({
    toolName: "read",
    toolCallId: "t-read",
    input: other,
    content: [{ type: "text", text: "readme" }],
  }),
  undefined,
);

console.log("OK: bash timeout cap clamps oversize and missing timeouts to 300s");
JS
