#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pi_bin=$(realpath "$(command -v pi)")
pi_package=$(cd "$(dirname "$pi_bin")/.." && pwd)
mkdir -p "$tmp/node_modules/@earendil-works" "$tmp/bin" "$tmp/home"
ln -s "$pi_package" "$tmp/node_modules/@earendil-works/pi-coding-agent"
ln -s "$pi_package/node_modules/typebox" "$tmp/node_modules/typebox"
ln -s "$root/common/pi/.pi/agent/extensions/agent-delegation.ts" "$tmp/agent-delegation.ts"
ln -s "$root/common/pi/.pi/agent/extensions/agent-delegation-watchdog.mjs" "$tmp/agent-delegation-watchdog.mjs"
cat >"$tmp/bin/pueue" <<'SH'
#!/bin/sh
case "$1" in
  add)
    printf '%s\0' "$@" >"$TEST_TMP/pueue-args"
    printf '%s\n' 7
    ;;
  wait)
    exit 0
    ;;
  log)
    printf '%s\n' 'Task 7: Failed' \
      'PI_DELEGATION_INACTIVITY: no parsed Pi lifecycle/progress event for 600s (last Pi event: message_update); sent SIGTERM to process group'
    ;;
  status)
    printf '%s\n' 'fake status'
    ;;
esac
SH
chmod +x "$tmp/bin/pueue"

cd "$tmp"
HOME="$tmp/home" TEST_TMP="$tmp" PATH="$tmp/bin:$PATH" node --experimental-transform-types --preserve-symlinks --input-type=module - "$tmp" <<'JS'
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import { readFileSync } from "node:fs";

const tmp = process.argv[2];
const {
  INACTIVITY_TIMEOUT_MS,
  TERMINATION_GRACE_MS,
  parsePiJsonLine,
  runWatchedProcess,
} = await import(`file://${tmp}/agent-delegation-watchdog.mjs`);
const { default: registerExtension, extractInactivityDiagnostic } = await import(`file://${tmp}/agent-delegation.ts`);

assert.equal(INACTIVITY_TIMEOUT_MS, 10 * 60 * 1000);
assert.equal(TERMINATION_GRACE_MS, 5 * 1000);

for (const type of [
  "agent_start",
  "message_update",
  "tool_execution_start",
  "tool_execution_update",
  "tool_execution_end",
  "agent_end",
]) {
  assert.equal(parsePiJsonLine(JSON.stringify({ type })).activityType, type);
}
for (const line of [
  "plain output",
  "{not-json}",
  JSON.stringify({ type: "session" }),
  JSON.stringify({ type: "message_end", message: { role: "assistant", content: [] } }),
]) {
  assert.equal(parsePiJsonLine(line).activityType, undefined);
}

class FakeClock {
  nowMs = 0;
  nextId = 1;
  timers = new Map();

  now = () => this.nowMs;
  setTimeout = (callback, delay) => {
    const id = this.nextId++;
    this.timers.set(id, { at: this.nowMs + delay, callback });
    return id;
  };
  clearTimeout = (id) => this.timers.delete(id);
  advance(ms) {
    const target = this.nowMs + ms;
    while (true) {
      const due = [...this.timers.entries()]
        .filter(([, timer]) => timer.at <= target)
        .sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
      if (!due) break;
      this.nowMs = due[1].at;
      this.timers.delete(due[0]);
      due[1].callback();
    }
    this.nowMs = target;
  }
}

class FakeChild extends EventEmitter {
  pid = 4242;
  stdout = new PassThrough();
  closed = false;
  close(code, signal = null) {
    if (this.closed) return;
    this.closed = true;
    this.stdout.end();
    this.emit("close", code, signal);
  }
}

function capture() {
  let value = "";
  return {
    stream: { write(chunk) { value += String(chunk); return true; } },
    value: () => value,
  };
}

function fixture({ closeOnTerm = true, descendantSurvivesTerm = false } = {}) {
  const clock = new FakeClock();
  const child = new FakeChild();
  const stdout = capture();
  const stderr = capture();
  const signals = [];
  let groupAlive = true;
  const promise = runWatchedProcess("pi", ["--mode", "json", "-p", "opaque prompt"], {
    inactivityMs: 100,
    terminationGraceMs: 20,
    now: clock.now,
    setTimeout: clock.setTimeout,
    clearTimeout: clock.clearTimeout,
    stdout: stdout.stream,
    stderr: stderr.stream,
    spawnProcess(command, args, options) {
      assert.equal(command, "pi");
      assert.deepEqual(args, ["--mode", "json", "-p", "opaque prompt"]);
      assert.equal(options.detached, true);
      assert.deepEqual(options.stdio, ["ignore", "pipe", "inherit"]);
      return child;
    },
    killProcessGroup(pid, signal) {
      assert.equal(pid, child.pid);
      signals.push(signal);
      if (signal === "SIGTERM" && closeOnTerm) {
        if (!descendantSurvivesTerm) groupAlive = false;
        child.close(null, signal);
      }
      if (signal === "SIGKILL") {
        groupAlive = false;
        child.close(null, signal);
      }
    },
    isProcessGroupAlive(pid) {
      assert.equal(pid, child.pid);
      return groupAlive;
    },
  });
  return { clock, child, stdout, stderr, signals, promise };
}

// A parsed streaming event resets the deadline; runtime alone does not expire it.
{
  const f = fixture();
  f.clock.advance(99);
  f.child.stdout.write(`${JSON.stringify({ type: "message_update", assistantMessageEvent: { type: "text_delta", delta: "x" } })}\n`);
  f.clock.advance(99);
  assert.deepEqual(f.signals, []);
  f.child.close(0);
  const result = await f.promise;
  assert.equal(result.timedOut, false);
  assert.equal(result.code, 0);
}

// Plain output is not activity, and silence before the first Pi event is diagnosed as startup silence.
{
  const f = fixture();
  f.clock.advance(50);
  f.child.stdout.write("plain output is not a Pi event\n");
  f.clock.advance(50);
  const result = await f.promise;
  assert.equal(result.timedOut, true);
  assert.deepEqual(f.signals, ["SIGTERM"]);
  assert.match(f.stderr.value(), /PI_DELEGATION_INACTIVITY:/);
  assert.match(f.stderr.value(), /startup silence/);
  assert.match(f.stderr.value(), /100ms/);
}

// Silence after a lifecycle event terminates the process group and records the last event.
{
  const f = fixture();
  f.child.stdout.write(`${JSON.stringify({ type: "agent_start" })}\n`);
  f.clock.advance(100);
  const result = await f.promise;
  assert.equal(result.timedOut, true);
  assert.equal(result.code, 124);
  assert.deepEqual(f.signals, ["SIGTERM"]);
  assert.match(f.stderr.value(), /last Pi event: agent_start/);
}

// A child that ignores SIGTERM is escalated once after the fixed grace period.
{
  const f = fixture({ closeOnTerm: false });
  f.child.stdout.write(`${JSON.stringify({ type: "tool_execution_start" })}\n`);
  f.clock.advance(100);
  assert.deepEqual(f.signals, ["SIGTERM"]);
  f.clock.advance(19);
  assert.deepEqual(f.signals, ["SIGTERM"]);
  f.clock.advance(1);
  const result = await f.promise;
  assert.equal(result.timedOut, true);
  assert.deepEqual(f.signals, ["SIGTERM", "SIGKILL"]);
  assert.match(f.stderr.value(), /escalated to SIGKILL after 20ms/);
}

// Direct Pi exit must not cancel escalation while a tool descendant remains in the process group.
{
  const f = fixture({ closeOnTerm: true, descendantSurvivesTerm: true });
  f.child.stdout.write(`${JSON.stringify({ type: "tool_execution_start" })}\n`);
  f.clock.advance(100);
  assert.equal(f.child.closed, true);
  assert.deepEqual(f.signals, ["SIGTERM"]);
  f.clock.advance(19);
  assert.deepEqual(f.signals, ["SIGTERM"]);
  f.clock.advance(1);
  const result = await f.promise;
  assert.equal(result.timedOut, true);
  assert.deepEqual(f.signals, ["SIGTERM", "SIGKILL"]);
  assert.match(f.stderr.value(), /escalated to SIGKILL after 20ms/);
}

// JSON mode's authoritative final assistant message remains useful pueue output.
{
  const f = fixture();
  f.child.stdout.write(`${JSON.stringify({
    type: "message_end",
    message: {
      role: "assistant",
      content: [
        { type: "thinking", thinking: "hidden" },
        { type: "text", text: "final " },
        { type: "text", text: "answer" },
      ],
    },
  })}\n`);
  f.child.stdout.write(`${JSON.stringify({ type: "agent_end", messages: [] })}\n`);
  f.child.close(0);
  const result = await f.promise;
  assert.equal(result.timedOut, false);
  assert.equal(f.stdout.value(), "final answer\n");
}

const diagnostic = extractInactivityDiagnostic([
  "unrelated pueue output",
  "PI_DELEGATION_INACTIVITY: no parsed Pi lifecycle/progress event for 600000ms (last Pi event: message_update); sent SIGTERM to process group",
].join("\n"));
assert.equal(
  diagnostic,
  "no parsed Pi lifecycle/progress event for 600000ms (last Pi event: message_update); sent SIGTERM to process group",
);
assert.equal(extractInactivityDiagnostic("ordinary provider failure"), undefined);

// The extension keeps prompt/model as argv, preserves the pueue stdin EOF shell, and surfaces the marker in check/wait.
{
  const tools = new Map();
  registerExtension({
    registerTool(tool) { tools.set(tool.name, tool); },
    on() {},
  });
  const task = `review $(touch ${tmp}/must-not-exist) and 'quotes'`;
  const queued = await tools.get("delegate_agent").execute("call-1", { task, mode: "async" });
  assert.match(queued.content[0].text, /Pueue task ID\*\*: 7/);
  const queuedArgs = readFileSync(`${tmp}/pueue-args`, "utf8").split("\0").filter(Boolean);
  assert.deepEqual(queuedArgs, [
    "add", "--escape", "--immediate", "--print-task-id", "--label", "pi-delegate", "--",
    "sh", "-c", 'exec "$@" </dev/null', "sh",
    process.execPath, `${tmp}/agent-delegation-watchdog.mjs`, "--",
    "pi", "--mode", "json", "--model", "openai-codex/gpt-5.4-mini:medium", "-p", task,
  ]);
  assert.throws(() => readFileSync(`${tmp}/must-not-exist`), /ENOENT/);

  const checked = await tools.get("check_delegation").execute("call-2", { taskId: "7" });
  assert.match(checked.content[0].text, /Inactivity watchdog: no parsed Pi lifecycle\/progress event for 600s/);
  assert.equal(checked.details.inactivityDiagnostic.includes("last Pi event: message_update"), true);

  const waited = await tools.get("wait_delegation").execute("call-3", { taskId: "7" });
  assert.match(waited.content[0].text, /failed the inactivity watchdog/);
  assert.equal(waited.details.completed, false);
  assert.equal(waited.details.inactivity, true);
}

console.log("OK: delegation watchdog uses parsed Pi activity, terminates inactive trees, and preserves final output");
JS
