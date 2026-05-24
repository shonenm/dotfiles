// Agent Delegation Extension for pi
//
// Spawn sub-agents for parallel work via pueue + pi -p.
// Supports natural language delegation and difficulty-based model auto-selection.
//
// Built-in agent roles (use in prompt/task description):
//   reviewer   — Code review, correctness, security audit
//   scout      — Codebase exploration, read-only research
//   worker     — Implementation from approved plan
//   oracle     — Second opinion, challenge assumptions, architecture advice
//
// Model selection tiers (from AGENTS.md):
//   high   → gpt-5.5:high / kimi-k2.6:high
//   medium → deepseek-v4-pro:high / gpt-5.4:low
//   low    → deepseek-v4-flash:off / gpt-5.4-mini:off

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { execSync, spawn } from "node:child_process";
import { existsSync, readFileSync, appendFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const DELEGATION_LOG = join(homedir(), ".pi", "research", "delegation.jsonl");

interface ModelTier {
  model: string;
  fallbackModels: string[];
}

const MODEL_TIERS: Record<string, ModelTier> = {
  high: {
    model: "opencode-go/kimi-k2.6:high",
    fallbackModels: [],
  },
  medium: {
    model: "opencode-go/deepseek-v4-pro:high",
    fallbackModels: [],
  },
  low: {
    model: "opencode-go/deepseek-v4-flash:off",
    fallbackModels: [],
  },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function ensureLogDir() {
  const dir = join(join(homedir(), ".pi", "research"));
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function logDelegation(difficulty: string, task: string, taskId?: string) {
  ensureLogDir();
  appendFileSync(DELEGATION_LOG, JSON.stringify({
    timestamp: new Date().toISOString(),
    difficulty,
    task: task.slice(0, 300),
    taskId: taskId ?? null,
  }) + "\n");
}

function buildPiCommand(task: string, difficulty: string, model?: string): string {
  const tier = MODEL_TIERS[difficulty] ?? MODEL_TIERS.medium;
  const m = model || tier.model;
  // Escape single quotes in task
  const escaped = task.replace(/'/g, "'\\''");
  return `pi --model '${m}' -p '${escaped}'`;
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  // -----------------------------------------------------------------------
  // Tool: delegate_agent
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "delegate_agent",
    label: "Delegate Agent",
    description:
      "Spawn a sub-agent (separate pi instance) for focused work. " +
      "Built-in roles: reviewer (code review), scout (codebase research), " +
      "worker (implement from plan), oracle (second opinion). " +
      "Supports sync (wait for result) and async (background via pueue) modes. " +
      "Use natural language in the task: 'Use reviewer to audit auth module for security issues'. " +
      "Difficulty auto-selects model: high=kimi-k2.6, medium=deepseek-v4-pro, low=deepseek-v4-flash.",
    promptSnippet: "Delegate a task to a sub-agent (reviewer/scout/worker/oracle)",
    promptGuidelines: [
      "Use delegate_agent for tasks that benefit from a second set of model eyes.",
      "Prefer role names in the task: 'Use reviewer to...', 'Use scout to explore...', 'Use oracle for a second opinion on...'.",
      "Run parallel reviewers for different concerns: correctness, tests, complexity.",
      "Use async mode (default) for independent work. Use sync for sequential dependencies.",
      "Difficulty: high=review/design/debug, medium=coding from plan, low=summaries.",
    ],
    parameters: Type.Object({
      task: Type.String({ description: "Task description/instructions for the sub-agent" }),
      difficulty: Type.Optional(Type.String({ description: "high, medium, or low. Default: medium" })),
      mode: Type.Optional(Type.String({ description: "'async' (pueue background) or 'sync' (wait). Default: 'async'" })),
      model: Type.Optional(Type.String({ description: "Override model (e.g., 'opencode-go/kimi-k2.6:high')" })),
    }),
    async execute(_toolCallId, params, _signal, onUpdate) {
      const difficulty = params.difficulty || "medium";
      const mode = params.mode || "async";
      const cmd = buildPiCommand(params.task, difficulty, params.model);

      if (mode === "sync") {
        onUpdate?.({ content: [{ type: "text", text: `🔄 Spawning sub-agent (${difficulty}, sync)...` }] });
        try {
          const result = execSync(cmd, {
            encoding: "utf-8",
            timeout: 600_000, // 10 min
            maxBuffer: 50 * 1024 * 1024,
            stdio: ["pipe", "pipe", "pipe"],
          });
          logDelegation(difficulty, params.task);
          return {
            content: [{
              type: "text",
              text: `## Sub-agent Result (${difficulty}, sync)\n\n${result.slice(0, 15000)}`,
            }],
            details: { difficulty, mode: "sync", model: cmd.split("--model ")[1]?.split(" ")[0] },
          };
        } catch (err: unknown) {
          const msg = err instanceof Error ? err.message : String(err);
          return {
            content: [{ type: "text", text: `❌ Sub-agent failed: ${msg.slice(0, 500)}` }],
            details: { difficulty, mode: "sync", error: msg.slice(0, 200) },
          };
        }
      }

      // Async mode: pueue
      onUpdate?.({ content: [{ type: "text", text: `📋 Queuing sub-agent (${difficulty}, async)...` }] });
      try {
        const pueueResult = execSync(`pueue add -i --print-task-id -- ${cmd} < /dev/null`, {
          encoding: "utf-8",
          timeout: 10_000,
          stdio: ["pipe", "pipe", "pipe"],
        });
        const taskId = pueueResult.trim();
        logDelegation(difficulty, params.task, taskId);

        return {
          content: [{
            type: "text",
            text: `## Sub-agent Queued (${difficulty}, async)\n\n` +
              `**Pueue task ID**: ${taskId}\n\n` +
              `Check status: \`pueue status\`\n` +
              `View log: \`pueue log ${taskId}\`\n` +
              `Wait for completion: \`pueue wait ${taskId}\``,
          }],
          details: { difficulty, mode: "async", pueueTaskId: taskId, model: cmd.split("--model ")[1]?.split(" ")[0] },
        };
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          content: [{ type: "text", text: `❌ Failed to queue task: ${msg}. Is pueue daemon running? (\`pueued -d\`)` }],
          details: { difficulty, mode: "async", error: msg.slice(0, 200) },
        };
      }
    },
  });

  // -----------------------------------------------------------------------
  // Tool: check_delegation
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "check_delegation",
    label: "Check Delegation",
    description: "Check the status of pueue tasks (sub-agents). Shows running, queued, and completed tasks.",
    promptSnippet: "Check status of delegated sub-agent tasks",
    parameters: Type.Object({
      taskId: Type.Optional(Type.String({ description: "Specific pueue task ID to check" })),
    }),
    async execute(_toolCallId, params) {
      try {
        if (params.taskId) {
          const log = execSync(`pueue log ${params.taskId}`, {
            encoding: "utf-8", timeout: 5000,
            stdio: ["pipe", "pipe", "pipe"],
          });
          return {
            content: [{ type: "text", text: `## Task ${params.taskId}\n\n\`\`\`\n${log.slice(-5000)}\n\`\`\`` }],
            details: { taskId: params.taskId },
          };
        }

        const status = execSync("pueue status", {
          encoding: "utf-8", timeout: 5000,
          stdio: ["pipe", "pipe", "pipe"],
        });
        return {
          content: [{ type: "text", text: `## Pueue Status\n\n\`\`\`\n${status.slice(0, 5000)}\n\`\`\`` }],
          details: {},
        };
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          content: [{ type: "text", text: `Pueue status unavailable: ${msg.slice(0, 300)}` }],
          details: { error: msg.slice(0, 200) },
        };
      }
    },
  });

  // -----------------------------------------------------------------------
  // Tool: wait_delegation
  // -----------------------------------------------------------------------
  pi.registerTool({
    name: "wait_delegation",
    label: "Wait Delegation",
    description: "Wait for a specific pueue task to complete and return its output.",
    promptSnippet: "Wait for a delegated task to finish",
    parameters: Type.Object({
      taskId: Type.String({ description: "Pueue task ID to wait for" }),
    }),
    async execute(_toolCallId, params, _signal, onUpdate) {
      onUpdate?.({ content: [{ type: "text", text: `⏳ Waiting for task ${params.taskId}...` }] });
      try {
        execSync(`pueue wait ${params.taskId}`, {
          encoding: "utf-8", timeout: 600_000, // 10 min
          stdio: ["pipe", "pipe", "pipe"],
        });
        const log = execSync(`pueue log ${params.taskId}`, {
          encoding: "utf-8", timeout: 5000,
          stdio: ["pipe", "pipe", "pipe"],
        });
        return {
          content: [{
            type: "text",
            text: `## Task ${params.taskId} Complete\n\n\`\`\`\n${log.slice(-8000)}\n\`\`\``,
          }],
          details: { taskId: params.taskId, completed: true },
        };
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          content: [{ type: "text", text: `❌ Task ${params.taskId} failed or timed out: ${msg.slice(0, 500)}` }],
          details: { taskId: params.taskId, error: msg.slice(0, 200) },
        };
      }
    },
  });

  // -----------------------------------------------------------------------
  // Notify on startup
  // -----------------------------------------------------------------------
  pi.on("session_start", async (_event, ctx) => {
    try {
      execSync("pueued -d", { timeout: 2000, stdio: "ignore" });
    } catch {
      // daemon may already be running
    }
    ctx.ui.notify(
      "Delegation: sync + async (pueue) sub-agents available",
      "info"
    );
  });
}
