import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { applyResultBudget } from "./budget.ts";
import { prepareToolParams, shapeResult } from "./shape.ts";

function pipelineFixture(): string {
  return JSON.stringify({
    number: 33075,
    status: "running",
    commit: "b1ad7d3f1234567890abcdef",
    event: "push",
    ref: "refs/heads/main",
    workflows: [
      { name: "gate", state: "success", children: Array.from({ length: 700 }, (_, id) => ({ id, name: `success-${id}`, state: "success", log: "x".repeat(20) })) },
      { name: "meta", state: "failure", children: [{ id: 1065572, name: "harness-fixtures", state: "failure", exit_code: 1 }] },
    ],
  });
}

test("budget writes the full body and returns a JSON envelope, never a prefix", async () => {
  const dir = await mkdtemp(join(tmpdir(), "mcp-overflow-"));
  const original = JSON.stringify({ value: "x".repeat(4000) });
  const result = applyResultBudget(original, 800, { overflowDir: dir });
  assert.equal(result.truncated, true);
  assert.ok(result.text.length <= 800);
  assert.notEqual(result.text, original.slice(0, 800));
  const envelope = JSON.parse(result.text) as { truncated: boolean; overflow: string; keys?: Record<string, number> };
  assert.equal(envelope.truncated, true);
  assert.equal(await readFile(join(dir, envelope.overflow.split("/").pop()!), "utf8"), original);
  assert.equal(envelope.keys?.value, Buffer.byteLength(JSON.stringify("x".repeat(4000)), "utf8"));
  assert.doesNotMatch(result.text, /xxxxx/);
});

test("pipeline summary keeps a failure after a large success section", async () => {
  const dir = await mkdtemp(join(tmpdir(), "mcp-overflow-"));
  const original = pipelineFixture();
  assert.ok(!original.slice(0, 8000).includes("harness-fixtures"));
  const shaped = shapeResult({ server: "woodpecker-ci", tool: "get_pipeline_status", text: original, params: {} });
  const budgeted = applyResultBudget(shaped.text, 8000, { originalText: original, omitted: shaped.omitted, overflowDir: dir });
  const summary = JSON.parse(budgeted.text) as {
    truncated: boolean;
    overflow: string;
    workflows: Array<{ name: string; failed_steps?: Array<{ id: number }> }>;
  };
  assert.equal(summary.workflows.find((workflow) => workflow.name === "meta")?.failed_steps?.[0]?.id, 1065572);
  assert.equal(budgeted.truncated, true);
  assert.equal(await readFile(join(dir, summary.overflow.split("/").pop()!), "utf8"), original);
});

test("unregistered JSON under budget passes through", () => {
  const result = shapeResult({ server: "other", tool: "unknown", text: JSON.stringify({ alpha: "secret", beta: [1, 2] }), params: {} });
  assert.equal(result.shape, "identity");
  assert.equal(result.omitted, false);
  assert.match(result.text, /secret/);
});

test("unregistered JSON over budget becomes inventory plus overflow", async () => {
  const dir = await mkdtemp(join(tmpdir(), "mcp-overflow-"));
  const original = JSON.stringify({ alpha: "secret", beta: [1, 2], blob: "x".repeat(4000) });
  const shaped = shapeResult({ server: "other", tool: "unknown", text: original, params: {} });
  const budgeted = applyResultBudget(shaped.text, 800, { originalText: original, omitted: shaped.omitted, overflowDir: dir });
  const envelope = JSON.parse(budgeted.text) as { truncated: boolean; keys: Record<string, number> };
  assert.equal(envelope.truncated, true);
  assert.ok(envelope.keys.alpha > 0);
  assert.doesNotMatch(budgeted.text, /secret/);
});

test("get_logs injects defaults only for woodpecker and preserves explicit values", () => {
  assert.deepEqual(prepareToolParams("woodpecker-ci", "get_logs", {}), { lines: 80, tail: true });
  assert.deepEqual(prepareToolParams("woodpecker-ci", "get_logs", { lines: 12, tail: false, detail: "full" }), { lines: 12, tail: false });
  assert.deepEqual(prepareToolParams("woodpecker-ci", "get_logs", { detail: "full" }), {});
  assert.deepEqual(prepareToolParams("woodpecker-ci", "get_logs", {}, "full"), {});
});

test("full detail skips shaping but still uses overflow", async () => {
  const dir = await mkdtemp(join(tmpdir(), "mcp-overflow-"));
  const original = JSON.stringify({ workflows: [{ name: "failure", children: [{ id: 1 }] }], value: "x".repeat(4000) });
  const shaped = shapeResult({ server: "woodpecker-ci", tool: "get_pipeline_status", text: original, params: { detail: "full" } });
  assert.equal(shaped.text, original);
  const budgeted = applyResultBudget(shaped.text, 800, { originalText: original, overflowDir: dir });
  const envelope = JSON.parse(budgeted.text) as { truncated: boolean };
  assert.equal(envelope.truncated, true);
  assert.ok(budgeted.text.length <= 800);
});

test("list_pipelines collapses commit messages to one line", () => {
  const result = shapeResult({ server: "woodpecker-ci", tool: "list_pipelines", text: JSON.stringify([{ commit: { message: "first line\nsecond line" } }]), params: {} });
  assert.equal(JSON.parse(result.text)[0].commit.message, "first line");
});
