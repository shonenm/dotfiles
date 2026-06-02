// Workflow Extension for pi
//
// Deterministic multi-agent orchestration over headless `pi` sub-agents — a
// pragmatic port of Claude Code's Workflow feature, built on pi's `--mode json`
// runner. Provides two model-callable tools:
//
//   agent_parallel  — fan out N independent tasks, run them concurrently
//   agent_pipeline  — push items through ordered stages (each item independent)
//
// Each sub-agent runs as `pi --mode json --no-session ...`; we parse the event
// stream for the final assistant text and sum per-message usage for a real
// token/cost budget. Structured output is best-effort: if `jsonKeys` is given we
// instruct the child to emit JSON and parse it (pi has no schema enforcement on
// the CLI). Recursion is capped at depth 1 (sub-agents cannot themselves fan out).

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { execFile } from "node:child_process";

const DEFAULT_CONCURRENCY = 4;
const DEFAULT_TIMEOUT_MS = 600_000; // 10 min per sub-agent
const DEPTH_ENV = "PI_WORKFLOW_DEPTH";

// Difficulty → model. Mirrors agent-delegation.ts; change per provider.
const MODEL_TIERS: Record<string, string> = {
  high: "opencode-go/kimi-k2.6:high",
  medium: "opencode-go/deepseek-v4-pro:high",
  low: "opencode-go/deepseek-v4-flash:off",
};
function resolveModel(difficulty?: string, model?: string): string {
  return model || MODEL_TIERS[difficulty ?? "medium"] || MODEL_TIERS.medium;
}

interface AgentResult {
  ok: boolean;
  text: string;
  json: unknown | null; // parsed object/array when jsonKeys requested and parse succeeded
  tokens: number;
  costUSD: number;
  error?: string;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

// Parse a `pi --mode json` stdout stream (newline-delimited event objects).
// Final answer = text of the last assistant message_end. Usage = sum of
// per-assistant-message usage (message_end only, to avoid double-counting
// turn_end / agent_end which repeat the same numbers).
export function parsePiJsonStream(stdout: string): { text: string; tokens: number; costUSD: number } {
  let text = "";
  let tokens = 0;
  let costUSD = 0;
  for (const line of stdout.split("\n")) {
    const t = line.trim();
    if (!t) continue;
    let ev: any;
    try { ev = JSON.parse(t); } catch { continue; }
    if (ev.type === "message_end" && ev.message?.role === "assistant") {
      const blocks = Array.isArray(ev.message.content) ? ev.message.content : [];
      const msgText = blocks
        .filter((b: any) => b?.type === "text")
        .map((b: any) => b.text ?? "")
        .join("");
      if (msgText) text = msgText; // keep the latest assistant text
      const u = ev.message.usage;
      if (u) {
        tokens += u.totalTokens ?? ((u.input ?? 0) + (u.output ?? 0));
        costUSD += u.cost?.total ?? 0;
      }
    }
  }
  return { text, tokens, costUSD };
}

// Extract a JSON value from possibly-fenced / prose-wrapped model text.
export function extractJson(text: string): unknown | null {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = (fenced ? fenced[1] : text).trim();
  const tryParse = (s: string): unknown | undefined => {
    try { return JSON.parse(s); } catch { return undefined; }
  };
  let v = tryParse(candidate);
  if (v !== undefined) return v;
  // Fall back to the first {...} / [...] span.
  const firstObj = candidate.indexOf("{");
  const firstArr = candidate.indexOf("[");
  const starts = [firstObj, firstArr].filter((n) => n >= 0);
  if (starts.length) {
    const s = Math.min(...starts);
    const e = Math.max(candidate.lastIndexOf("}"), candidate.lastIndexOf("]"));
    if (e > s) {
      v = tryParse(candidate.slice(s, e + 1));
      if (v !== undefined) return v;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

function runAgent(prompt: string, opts: { model: string; jsonKeys?: string[]; timeoutMs?: number }): Promise<AgentResult> {
  const args = ["--mode", "json", "--no-session", "--model", opts.model];
  if (opts.jsonKeys && opts.jsonKeys.length) {
    args.push(
      "--append-system-prompt",
      `Return ONLY a single JSON object (no prose, no markdown fence) with these keys: ${opts.jsonKeys.join(", ")}.`
    );
  }
  args.push("-p", prompt);

  // Mark sub-process depth so a sub-agent can't itself fan out (recursion guard).
  const env = { ...process.env, [DEPTH_ENV]: String(currentDepth() + 1) };

  return new Promise<AgentResult>((resolve) => {
    execFile(
      "pi",
      args,
      { timeout: opts.timeoutMs ?? DEFAULT_TIMEOUT_MS, maxBuffer: 64 * 1024 * 1024, encoding: "utf-8", env },
      (err, stdout, stderr) => {
        const parsed = parsePiJsonStream(stdout || "");
        if (err && !parsed.text) {
          resolve({
            ok: false, text: "", json: null,
            tokens: parsed.tokens, costUSD: parsed.costUSD,
            error: String(stderr || (err as Error).message || "").slice(0, 500),
          });
          return;
        }
        const json = opts.jsonKeys && opts.jsonKeys.length ? extractJson(parsed.text) : null;
        resolve({ ok: true, text: parsed.text, json, tokens: parsed.tokens, costUSD: parsed.costUSD });
      }
    );
  });
}

function currentDepth(): number {
  const v = Number(process.env[DEPTH_ENV]);
  return Number.isFinite(v) ? v : 0;
}

// Concurrency-limited map preserving input order.
export async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T, index: number) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  const n = Math.max(1, Math.min(limit, items.length));
  const workers = Array.from({ length: n }, async () => {
    while (true) {
      const idx = next++;
      if (idx >= items.length) break;
      results[idx] = await fn(items[idx], idx);
    }
  });
  await Promise.all(workers);
  return results;
}

// ---------------------------------------------------------------------------
// Tool input shapes
// ---------------------------------------------------------------------------

const TaskSpec = Type.Object({
  task: Type.String({ description: "Instruction for the sub-agent" }),
  difficulty: Type.Optional(Type.String({ description: "high | medium | low (model tier). Default medium" })),
  model: Type.Optional(Type.String({ description: "Override model id (e.g. opencode-go/kimi-k2.6:high)" })),
  jsonKeys: Type.Optional(Type.Array(Type.String(), { description: "If set, instruct the sub-agent to return JSON with these keys and parse it" })),
});

const StageSpec = Type.Object({
  prompt: Type.String({ description: "Stage prompt. Use {input} for the previous stage's output and {item} for the original item." }),
  difficulty: Type.Optional(Type.String({ description: "high | medium | low. Default medium" })),
  model: Type.Optional(Type.String({ description: "Override model id" })),
  jsonKeys: Type.Optional(Type.Array(Type.String(), { description: "If set, return+parse JSON with these keys" })),
});

function budgetExceeded(spent: number, budgetUSD?: number): boolean {
  return typeof budgetUSD === "number" && budgetUSD > 0 && spent >= budgetUSD;
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "agent_parallel",
    label: "Agent Parallel",
    description:
      "Fan out independent tasks to concurrent headless sub-agents and collect their results. " +
      "Use for parallel work: multi-file review, broad search, independent drafts. " +
      "Returns each sub-agent's output plus total tokens/cost. Set jsonKeys per task for structured output. " +
      "Difficulty selects the model tier (high/medium/low).",
    promptSnippet: "Run independent tasks concurrently across sub-agents",
    promptGuidelines: [
      "Use agent_parallel when tasks are independent and benefit from concurrency.",
      "Set jsonKeys when you need to machine-read each result.",
      "Set budgetUSD to cap spend; tasks beyond the budget are skipped.",
    ],
    parameters: Type.Object({
      tasks: Type.Array(TaskSpec, { description: "Independent tasks to run concurrently" }),
      concurrency: Type.Optional(Type.Number({ description: `Max concurrent sub-agents (default ${DEFAULT_CONCURRENCY})` })),
      budgetUSD: Type.Optional(Type.Number({ description: "Optional total cost cap in USD; remaining tasks skipped once reached" })),
    }),
    async execute(_id, params, _signal, onUpdate) {
      if (currentDepth() > 0) {
        return {
          content: [{ type: "text", text: "❌ agent_parallel is disabled inside a sub-agent (recursion depth cap = 1)." }],
          details: { blocked: "recursion" },
        };
      }
      const tasks = params.tasks ?? [];
      if (tasks.length === 0) {
        return { content: [{ type: "text", text: "No tasks provided." }], details: { count: 0 } };
      }
      const concurrency = params.concurrency ?? DEFAULT_CONCURRENCY;
      let spent = 0;
      let done = 0;

      const results = await mapLimit(tasks, concurrency, async (t) => {
        if (budgetExceeded(spent, params.budgetUSD)) {
          return { skipped: true as const, task: t.task };
        }
        const r = await runAgent(t.task, { model: resolveModel(t.difficulty, t.model), jsonKeys: t.jsonKeys });
        spent += r.costUSD;
        done++;
        onUpdate?.({ content: [{ type: "text", text: `⚙️ ${done}/${tasks.length} done · $${spent.toFixed(3)}` }] });
        return { skipped: false as const, task: t.task, ...r };
      });

      const lines = results.map((r, i) => {
        if ("skipped" in r && r.skipped) return `${i + 1}. ⏭️ skipped (budget): ${r.task.slice(0, 60)}`;
        const rr = r as AgentResult & { task: string };
        const head = rr.ok ? "✅" : "❌";
        const body = rr.ok ? (rr.json ? JSON.stringify(rr.json) : rr.text) : (rr.error ?? "error");
        return `${i + 1}. ${head} ${rr.task.slice(0, 60)}\n${String(body).slice(0, 1500)}`;
      });

      return {
        content: [{ type: "text", text: `## agent_parallel (${tasks.length} tasks, $${spent.toFixed(3)})\n\n${lines.join("\n\n")}` }],
        details: {
          count: tasks.length,
          totalCostUSD: spent,
          results: results.map((r) => ("skipped" in r && r.skipped
            ? { skipped: true }
            : { ok: (r as AgentResult).ok, tokens: (r as AgentResult).tokens, costUSD: (r as AgentResult).costUSD, json: (r as AgentResult).json })),
        },
      };
    },
  });

  pi.registerTool({
    name: "agent_pipeline",
    label: "Agent Pipeline",
    description:
      "Push each item through an ordered list of stages. Every item runs independently and concurrently; " +
      "within an item, stages run in sequence and each stage sees the previous stage's output via {input} " +
      "(and the original item via {item}). Use for map-style transforms: e.g. for each file, summarize then critique. " +
      "Returns the final output per item plus total tokens/cost.",
    promptSnippet: "Run each item through ordered sub-agent stages",
    promptGuidelines: [
      "Use agent_pipeline for per-item multi-step transforms (summarize→verify, draft→refine).",
      "Reference {input} (previous stage output) and {item} (original item) in stage prompts.",
    ],
    parameters: Type.Object({
      items: Type.Array(Type.String(), { description: "Items to process independently (each runs through all stages)" }),
      stages: Type.Array(StageSpec, { description: "Ordered stages applied to each item" }),
      concurrency: Type.Optional(Type.Number({ description: `Max concurrent items (default ${DEFAULT_CONCURRENCY})` })),
      budgetUSD: Type.Optional(Type.Number({ description: "Optional total cost cap in USD" })),
    }),
    async execute(_id, params, _signal, onUpdate) {
      if (currentDepth() > 0) {
        return {
          content: [{ type: "text", text: "❌ agent_pipeline is disabled inside a sub-agent (recursion depth cap = 1)." }],
          details: { blocked: "recursion" },
        };
      }
      const items = params.items ?? [];
      const stages = params.stages ?? [];
      if (items.length === 0 || stages.length === 0) {
        return { content: [{ type: "text", text: "Provide both items and stages." }], details: {} };
      }
      const concurrency = params.concurrency ?? DEFAULT_CONCURRENCY;
      let spent = 0;
      let finished = 0;

      const results = await mapLimit(items, concurrency, async (item) => {
        let prev = "";
        let lastJson: unknown | null = null;
        for (const stage of stages) {
          if (budgetExceeded(spent, params.budgetUSD)) {
            return { item, ok: false as const, text: prev, json: lastJson, error: "budget reached", tokens: 0, costUSD: 0 };
          }
          const prompt = stage.prompt.split("{input}").join(prev).split("{item}").join(item);
          const r = await runAgent(prompt, { model: resolveModel(stage.difficulty, stage.model), jsonKeys: stage.jsonKeys });
          spent += r.costUSD;
          if (!r.ok) return { item, ok: false as const, text: r.text, json: r.json, error: r.error, tokens: r.tokens, costUSD: r.costUSD };
          prev = r.text;
          lastJson = r.json;
        }
        finished++;
        onUpdate?.({ content: [{ type: "text", text: `⚙️ ${finished}/${items.length} items · $${spent.toFixed(3)}` }] });
        return { item, ok: true as const, text: prev, json: lastJson, tokens: 0, costUSD: 0 };
      });

      const lines = results.map((r, i) => {
        const head = r.ok ? "✅" : "❌";
        const body = r.ok ? (r.json ? JSON.stringify(r.json) : r.text) : (r.error ?? "error");
        return `${i + 1}. ${head} ${String(r.item).slice(0, 50)}\n${String(body).slice(0, 1500)}`;
      });

      return {
        content: [{ type: "text", text: `## agent_pipeline (${items.length} items × ${stages.length} stages, $${spent.toFixed(3)})\n\n${lines.join("\n\n")}` }],
        details: { items: items.length, stages: stages.length, totalCostUSD: spent },
      };
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    if (currentDepth() === 0) {
      ctx.ui.notify("Workflow: agent_parallel / agent_pipeline available", "info");
    }
  });
}
