#!/usr/bin/env node

import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { createInterface } from "node:readline";

export const INACTIVITY_TIMEOUT_MS = 10 * 60 * 1000;
export const TERMINATION_GRACE_MS = 5 * 1000;
export const INACTIVITY_DIAGNOSTIC_PREFIX = "PI_DELEGATION_INACTIVITY:";

const ACTIVITY_EVENT_TYPES = new Set([
  "agent_start",
  "message_update",
  "tool_execution_start",
  "tool_execution_update",
  "tool_execution_end",
  "agent_end",
]);

export function parsePiJsonLine(line) {
  let event;
  try {
    event = JSON.parse(line);
  } catch {
    return {};
  }
  if (!event || typeof event !== "object") return {};

  const parsed = {};
  if (ACTIVITY_EVENT_TYPES.has(event.type)) parsed.activityType = event.type;
  if (event.type === "message_end" && event.message?.role === "assistant") {
    const blocks = Array.isArray(event.message.content) ? event.message.content : [];
    parsed.finalText = blocks
      .filter((block) => block?.type === "text")
      .map((block) => typeof block.text === "string" ? block.text : "")
      .join("");
  }
  return parsed;
}

function formatDuration(milliseconds) {
  return milliseconds % 1000 === 0 ? `${milliseconds / 1000}s` : `${milliseconds}ms`;
}

function inactivityDiagnostic(inactivityMs, lastActivityType) {
  const phase = lastActivityType
    ? `last Pi event: ${lastActivityType}`
    : "startup silence before the first Pi event";
  return `${INACTIVITY_DIAGNOSTIC_PREFIX} no parsed Pi lifecycle/progress event for ${formatDuration(inactivityMs)} (${phase}); sent SIGTERM to process group`;
}

export function runWatchedProcess(command, args, options = {}) {
  const inactivityMs = options.inactivityMs ?? INACTIVITY_TIMEOUT_MS;
  const terminationGraceMs = options.terminationGraceMs ?? TERMINATION_GRACE_MS;
  const now = options.now ?? Date.now;
  const setTimer = options.setTimeout ?? setTimeout;
  const clearTimer = options.clearTimeout ?? clearTimeout;
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;
  const spawnProcess = options.spawnProcess ?? spawn;
  const killProcessGroup = options.killProcessGroup ?? ((pid, signal) => process.kill(-pid, signal));
  const isProcessGroupAlive = options.isProcessGroupAlive ?? ((pid) => {
    try {
      process.kill(-pid, 0);
      return true;
    } catch (error) {
      if (error?.code === "ESRCH") return false;
      throw error;
    }
  });
  const installSignalHandlers = options.installSignalHandlers ?? true;

  return new Promise((resolveResult) => {
    const child = spawnProcess(command, args, {
      detached: true,
      stdio: ["ignore", "pipe", "inherit"],
    });
    const startedAt = now();
    let lastActivityAt = startedAt;
    let lastActivityType;
    let finalText;
    let inactivityTimer;
    let killTimer;
    let groupExitTimer;
    let timedOut = false;
    let finished = false;
    let childClosed = false;
    let closeCode;
    let closeSignal;
    let spawnError;
    let forwardedSignal;

    const safeKill = (signal) => {
      if (!child.pid) return;
      try {
        killProcessGroup(child.pid, signal);
      } catch (error) {
        if (error?.code !== "ESRCH") throw error;
      }
    };

    const groupIsAlive = () => Boolean(child.pid && isProcessGroupAlive(child.pid));

    const armDeadline = () => {
      if (inactivityTimer !== undefined) clearTimer(inactivityTimer);
      inactivityTimer = setTimer(onInactive, inactivityMs);
    };

    const signalHandlers = new Map();
    if (installSignalHandlers) {
      for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
        const handler = () => {
          forwardedSignal = signal;
          safeKill(signal);
        };
        signalHandlers.set(signal, handler);
        process.once(signal, handler);
      }
    }

    const cleanup = () => {
      if (inactivityTimer !== undefined) clearTimer(inactivityTimer);
      if (killTimer !== undefined) clearTimer(killTimer);
      if (groupExitTimer !== undefined) clearTimer(groupExitTimer);
      for (const [signal, handler] of signalHandlers) process.removeListener(signal, handler);
    };

    const finish = () => {
      if (finished) return;
      finished = true;
      cleanup();
      lines.close();
      if (finalText !== undefined) stdout.write(`${finalText}\n`);
      if (spawnError) stderr.write(`pi delegation watchdog could not start child: ${spawnError.message}\n`);
      resolveResult({
        code: timedOut ? 124 : (closeCode ?? (closeSignal ? null : 1)),
        signal: closeSignal,
        forwardedSignal,
        timedOut,
        lastActivityAt,
        lastActivityType,
      });
    };

    const waitForGroupExit = () => {
      if (finished) return;
      if (!groupIsAlive()) {
        if (childClosed) finish();
        return;
      }
      groupExitTimer = setTimer(waitForGroupExit, 50);
    };

    const onInactive = () => {
      if (finished) return;
      timedOut = true;
      stderr.write(`${inactivityDiagnostic(inactivityMs, lastActivityType)}\n`);
      safeKill("SIGTERM");
      if (childClosed && !groupIsAlive()) {
        finish();
        return;
      }
      killTimer = setTimer(() => {
        if (finished) return;
        if (groupIsAlive()) {
          stderr.write(`${INACTIVITY_DIAGNOSTIC_PREFIX} process group did not exit; escalated to SIGKILL after ${formatDuration(terminationGraceMs)}\n`);
          safeKill("SIGKILL");
        }
        if (childClosed && !groupIsAlive()) finish();
        else waitForGroupExit();
      }, terminationGraceMs);
    };

    const lines = createInterface({ input: child.stdout, crlfDelay: Infinity });
    lines.on("line", (line) => {
      const parsed = parsePiJsonLine(line);
      if (parsed.activityType) {
        lastActivityAt = now();
        lastActivityType = parsed.activityType;
        armDeadline();
      }
      if (parsed.finalText) finalText = parsed.finalText;
    });

    child.on("error", (error) => {
      spawnError = error;
    });
    child.on("close", (code, signal) => {
      childClosed = true;
      closeCode = code;
      closeSignal = signal;
      if (!timedOut || !groupIsAlive()) finish();
    });

    armDeadline();
  });
}

async function main() {
  const separator = process.argv[2] === "--" ? 3 : 2;
  const command = process.argv[separator];
  const args = process.argv.slice(separator + 1);
  if (!command) {
    process.stderr.write("Usage: agent-delegation-watchdog.mjs -- <command> [args...]\n");
    process.exitCode = 2;
    return;
  }

  const result = await runWatchedProcess(command, args);
  if (result.timedOut) {
    process.exitCode = 124;
  } else if (result.signal) {
    process.kill(process.pid, result.signal);
  } else {
    process.exitCode = result.code ?? 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
