// Pi UI shell: one owner for header, composer, footer, working indicator, and tab title.
// Keeps the original rich telemetry while adding responsive profiles and /status.

import type { AssistantMessage } from "@earendil-works/pi-ai";
import {
  CustomEditor,
  VERSION,
  type ExtensionAPI,
  type ExtensionContext,
  type Theme,
} from "@earendil-works/pi-coding-agent";
import {
  matchesKey,
  truncateToWidth,
  visibleWidth,
  type Focusable,
} from "@earendil-works/pi-tui";
import { execFileSync, execSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";

type DisplayMode = "off" | "minimal" | "compact" | "balanced" | "detailed" | "legacy";
type EditorFactory = NonNullable<ReturnType<ExtensionContext["ui"]["getEditorComponent"]>>;
type ShellEditorFactory = EditorFactory & { __piUiShell?: true };

const MODE_FILE = join(homedir(), ".pi", "agent", "statusline-mode");
const GOAL_FILE = join(homedir(), ".pi", "agent", "goal");
const DIRTY_CHECK_INTERVAL_MS = 5000;
const STATS_CACHE_TTL = 10_000;

function loadMode(): DisplayMode {
  try {
    const value = readFileSync(MODE_FILE, "utf-8").trim();
    if (["off", "minimal", "compact", "balanced", "detailed", "legacy"].includes(value)) {
      return value as DisplayMode;
    }
  } catch { /* default below */ }
  return "detailed";
}

function saveMode(value: DisplayMode): void {
  try { writeFileSync(MODE_FILE, value); } catch { /* non-fatal */ }
}

let mode = loadMode();
let dirtyState = false;
let lastDirtyCheck = 0;
let goalCache = "";
let currentTool = "";
let running = false;
let latestStatuses: string[] = [];
let tokCache = { input: 0, output: 0, cost: 0 };
let agentStatus = { running: 0, queued: 0 };
let cursorLimits = "";

interface StatsSnapshot {
  webSearch: number;
  webFetch: number;
  webCache: number;
  mcpCalls: number;
  mcpErrors: number;
}

let cachedStats: StatsSnapshot | null = null;
let statsCacheMs = 0;

function recomputeTokens(branch: Iterable<{ type: string; message?: { role: string } }>): void {
  let input = 0, output = 0, cost = 0;
  for (const entry of branch) {
    if (entry.type !== "message" || entry.message?.role !== "assistant") continue;
    const message = entry.message as unknown as AssistantMessage;
    input += message.usage.input;
    output += message.usage.output;
    cost += message.usage.cost.total;
  }
  tokCache = { input, output, cost };
}

function checkGitDirty(): boolean {
  try {
    return execSync("git status --porcelain", {
      encoding: "utf-8",
      timeout: 1000,
      stdio: ["pipe", "pipe", "ignore"],
    }).trim().length > 0;
  } catch { return false; }
}

function refreshGoal(): void {
  try { goalCache = readFileSync(GOAL_FILE, "utf-8").trim(); } catch { goalCache = ""; }
}

function refreshStats(): StatsSnapshot {
  const now = Date.now();
  if (cachedStats && now - statsCacheMs < STATS_CACHE_TTL) return cachedStats;

  const stats: StatsSnapshot = { webSearch: 0, webFetch: 0, webCache: 0, mcpCalls: 0, mcpErrors: 0 };
  const dir = join(homedir(), ".pi", "research");
  try {
    const web = JSON.parse(readFileSync(join(dir, "stats.json"), "utf-8"));
    stats.webSearch = web.searchCount ?? 0;
    stats.webFetch = web.fetchCount ?? 0;
    stats.webCache = web.cacheHits ?? 0;
  } catch { /* absent or invalid */ }
  try {
    const mcp = JSON.parse(readFileSync(join(dir, "mcp-stats.json"), "utf-8"));
    for (const value of Object.values(mcp) as Array<{ calls?: number; errors?: number }>) {
      stats.mcpCalls += value.calls ?? 0;
      stats.mcpErrors += value.errors ?? 0;
    }
  } catch { /* absent or invalid */ }
  cachedStats = stats;
  statsCacheMs = now;
  return stats;
}

function refreshCursorLimits(): void {
  try {
    const rows = execFileSync("ai-usage", ["cursor"], {
      encoding: "utf-8",
      timeout: 6000,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim().split("\n");
    cursorLimits = rows.map((row) => {
      const [, label, , pct, remaining] = row.split("\x1f");
      return label && label !== "--" ? `${label} ${pct}${remaining ? ` ${remaining}` : ""}` : "";
    }).filter(Boolean).join(" · ");
  } catch { cursorLimits = ""; }
}

function refreshAgents(): void {
  let active = 0, queued = 0;
  try {
    const data = JSON.parse(execSync("pueue status --json", {
      encoding: "utf-8",
      timeout: 1500,
      stdio: ["pipe", "pipe", "ignore"],
    }));
    const tasks = (data.tasks ?? {}) as Record<string, { label?: string; status?: unknown }>;
    for (const task of Object.values(tasks)) {
      if (task?.label !== "pi-delegate") continue;
      const state = typeof task.status === "string" ? task.status : Object.keys(task.status ?? {})[0];
      if (state === "Running") active++;
      else if (state === "Queued" || state === "Paused") queued++;
    }
  } catch { /* pueue unavailable */ }
  agentStatus = { running: active, queued };
}

function refreshSnapshot(ctx: ExtensionContext, includeRemote = false): void {
  recomputeTokens(ctx.sessionManager.getBranch());
  refreshGoal();
  refreshAgents();
  refreshStats();
  if (includeRemote) refreshCursorLimits();
  const now = Date.now();
  if (now - lastDirtyCheck > DIRTY_CHECK_INTERVAL_MS) {
    dirtyState = checkGitDirty();
    lastDirtyCheck = now;
  }
}

function formatTokens(value: number): string {
  if (value < 1000) return `${value}`;
  if (value < 1_000_000) return `${(value / 1000).toFixed(1)}k`;
  return `${(value / 1_000_000).toFixed(1)}M`;
}

function formatCwd(cwd: string): string {
  const home = homedir();
  return cwd === home ? "~" : cwd.startsWith(`${home}/`) ? `~/${cwd.slice(home.length + 1)}` : cwd;
}

function cleanStatus(value: string): string {
  return value.replace(/\x1b\[[0-9;]*m/g, "").replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim();
}

function balanceLine(left: string, right: string, width: number): string {
  if (!left) return truncateToWidth(right, width);
  if (!right) return truncateToWidth(left, width);
  const rightWidth = visibleWidth(right);
  if (rightWidth >= width - 3) return truncateToWidth(right, width);
  const fittedLeft = truncateToWidth(left, width - rightWidth - 3);
  return truncateToWidth(fittedLeft + " ".repeat(Math.max(3, width - visibleWidth(fittedLeft) - rightWidth)) + right, width);
}

function wrapGroups(groups: string[], width: number, separator: string): string[] {
  const lines: string[] = [];
  let line = "";
  for (const group of groups.filter(Boolean)) {
    const candidate = line ? line + separator + group : group;
    if (line && visibleWidth(candidate) > width) {
      lines.push(truncateToWidth(line, width));
      line = group;
    } else {
      line = candidate;
    }
  }
  if (line) lines.push(truncateToWidth(line, width));
  return lines;
}

function prioritizedLine(groups: Array<{ text: string; priority: number }>, width: number, separator: string): string {
  const selected: typeof groups = [];
  for (const group of [...groups].filter(({ text }) => text).sort((a, b) => a.priority - b.priority)) {
    const candidate = [...selected, group].sort((a, b) => groups.indexOf(a) - groups.indexOf(b));
    if (visibleWidth(candidate.map(({ text }) => text).join(separator)) <= width) selected.push(group);
  }
  return truncateToWidth(selected.sort((a, b) => groups.indexOf(a) - groups.indexOf(b)).map(({ text }) => text).join(separator), width);
}

function fitBorder(left: string, right: string, width: number, paint: (text: string) => string): string {
  if (width <= 1) return paint("─".repeat(Math.max(0, width)));
  let lhs = left, rhs = right;
  while (visibleWidth(lhs) + visibleWidth(rhs) + 5 > width && visibleWidth(rhs) > 0) {
    rhs = truncateToWidth(rhs, visibleWidth(rhs) - 1, "");
  }
  while (visibleWidth(lhs) + visibleWidth(rhs) + 5 > width && visibleWidth(lhs) > 0) {
    lhs = truncateToWidth(lhs, visibleWidth(lhs) - 1, "");
  }
  return paint("─") + lhs + paint("─".repeat(Math.max(1, width - visibleWidth(lhs) - visibleWidth(rhs) - 2))) + rhs + paint("─");
}

function contextLabel(ctx: ExtensionContext): string {
  const usage = ctx.getContextUsage();
  return usage?.percent === null || usage?.percent === undefined ? "CTX ?" : `CTX ${Math.round(usage.percent)}%`;
}

function setTabTitle(ctx: ExtensionContext, state: string): void {
  ctx.ui.setTitle(`π ${state} · ${basename(ctx.cwd)}`);
}

function installHeader(ctx: ExtensionContext): void {
  ctx.ui.setHeader((_tui, theme) => ({
    render(width: number): string[] {
      const mark = theme.bold(theme.fg("accent", "π"));
      const title = theme.bold(theme.fg("text", "CODING SHELL"));
      const meta = theme.fg("muted", `${ctx.model?.id ?? "no-model"} · ${formatCwd(ctx.cwd)}`);
      const first = balanceLine(` ${mark}  ${title}`, theme.fg("dim", `v${VERSION}`), width);
      return width < 48 ? [first] : [first, truncateToWidth(` ${theme.fg("dim", "╰─")} ${meta}`, width)];
    },
    invalidate() {},
  }));
}

function installEditor(pi: ExtensionAPI, ctx: ExtensionContext): void {
  const existing = ctx.ui.getEditorComponent() as ShellEditorFactory | undefined;
  if (existing?.__piUiShell) return;

  const factory: ShellEditorFactory = (tui, editorTheme, keybindings) => {
    const editor = existing
      ? existing(tui, editorTheme, keybindings)
      : new CustomEditor(tui, editorTheme, keybindings, { paddingX: 0 });
    const render = editor.render.bind(editor);
    editor.render = (width) => {
      const lines = render(width);
      if (lines.length < 2) return lines;
      const theme = ctx.ui.theme;
      const state = currentTool ? ` TOOL · ${currentTool} ` : running ? " RUN " : " ASK ";
      const stateColor = currentTool ? "warning" : running ? "accent" : "success";
      const topLeft = theme.bold(theme.fg(stateColor, state));
      const topRight = theme.fg("dim", ` ${pi.getThinkingLevel()} `);
      const bottomLeft = theme.fg("muted", ` ${ctx.model?.id ?? "no-model"} · ${contextLabel(ctx)} `);
      const bottomRight = theme.fg("dim", " /status ");
      lines[0] = fitBorder(topLeft, topRight, width, (text) => theme.fg(stateColor, text));
      lines[lines.length - 1] = fitBorder(bottomLeft, bottomRight, width, (text) => theme.fg("border", text));
      return lines;
    };
    return editor;
  };
  factory.__piUiShell = true;
  ctx.ui.setEditorComponent(factory);
}

class StatusOverlay implements Focusable {
  focused = false;
  readonly width = Math.max(36, Math.min(84, (process.stdout.columns || 88) - 4));

  constructor(
    private readonly theme: Theme,
    private readonly lines: Array<[string, string]>,
    private readonly done: () => void,
  ) {}

  handleInput(data: string): void {
    if (matchesKey(data, "escape") || matchesKey(data, "return") || data === "q") this.done();
  }

  render(): string[] {
    const inner = this.width - 2;
    const border = (text: string) => this.theme.fg("border", text);
    const row = (text = "") => {
      const clipped = truncateToWidth(` ${text}`, inner);
      return border("│") + clipped + " ".repeat(Math.max(0, inner - visibleWidth(clipped))) + border("│");
    };
    const output = [
      border(`╭${"─".repeat(inner)}╮`),
      row(`${this.theme.bold(this.theme.fg("accent", "π  SESSION STATUS"))}  ${this.theme.fg("dim", `profile: ${mode}`)}`),
      row(),
    ];
    for (const [label, value] of this.lines) {
      output.push(row(`${this.theme.fg("muted", label.padEnd(10))} ${value || this.theme.fg("dim", "—")}`));
    }
    output.push(row(), row(this.theme.fg("dim", "Esc / Enter / q  close")), border(`╰${"─".repeat(inner)}╯`));
    return output;
  }
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("statusline", {
    description: "Set UI profile: detailed, balanced, minimal, legacy, or off",
    getArgumentCompletions: () => [
      { value: "detailed", label: "Rich responsive telemetry" },
      { value: "balanced", label: "Two compact rails" },
      { value: "minimal", label: "One priority-driven rail" },
      { value: "legacy", label: "Original three-rail layout" },
      { value: "off", label: "Disable the footer" },
    ],
    handler: async (args, ctx) => {
      const requested = args.trim() === "compact" ? "balanced" : args.trim();
      if (["off", "minimal", "balanced", "detailed", "legacy"].includes(requested)) {
        mode = requested as DisplayMode;
      } else {
        const cycle: DisplayMode[] = ["detailed", "balanced", "minimal", "off"];
        mode = cycle[(cycle.indexOf(mode) + 1) % cycle.length]!;
      }
      saveMode(mode);
      if (mode === "off") ctx.ui.setFooter(undefined);
      else installFooter(ctx);
      ctx.ui.notify(`UI profile: ${mode}`, "info");
    },
  });

  pi.registerCommand("status", {
    description: "Show full Pi session telemetry",
    handler: async (_args, ctx) => {
      refreshSnapshot(ctx, true);
      const stats = refreshStats();
      const usage = ctx.getContextUsage();
      await ctx.ui.custom<void>(
        (_tui, theme, _keybindings, done) => new StatusOverlay(theme, [
          ["PROJECT", `${formatCwd(ctx.cwd)}${dirtyState ? "  *dirty" : ""}`],
          ["MODEL", `${ctx.model?.provider ?? "—"}/${ctx.model?.id ?? "—"} · ${pi.getThinkingLevel()}`],
          ["CONTEXT", usage?.percent == null ? "unknown" : `${usage.percent.toFixed(1)}% / ${formatTokens(usage.contextWindow ?? 0)}`],
          ["TOKENS", `↑${formatTokens(tokCache.input)}  ↓${formatTokens(tokCache.output)}  $${tokCache.cost.toFixed(3)}`],
          ["CURSOR", cursorLimits],
          ["AGENTS", `running ${agentStatus.running} · queued ${agentStatus.queued}`],
          ["WEB", `search ${stats.webSearch} · fetch ${stats.webFetch} · cache ${stats.webCache}`],
          ["MCP", `calls ${stats.mcpCalls} · errors ${stats.mcpErrors}`],
          ["GOAL", goalCache],
          ["STATUS", latestStatuses.join(" · ")],
        ], () => done()),
        { overlay: true },
      );
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    refreshSnapshot(ctx, true);
    installShell(pi, ctx);
    setTabTitle(ctx, dirtyState ? "●" : "READY");
  });

  // resources_discover runs after package session handlers. Re-applying here
  // makes this extension the deterministic owner while preserving wrapped editor behavior.
  pi.on("resources_discover", async (_event, ctx) => {
    installShell(pi, ctx);
    setImmediate(() => installShell(pi, ctx));
  });

  pi.on("agent_start", async (_event, ctx) => {
    running = true;
    currentTool = "";
    ctx.ui.setStatus("run-control", "RUN · Esc stop · Enter steer");
    setTabTitle(ctx, "RUN");
  });

  pi.on("tool_execution_start", async (event, ctx) => {
    currentTool = event.toolName;
    ctx.ui.setStatus("run-control", `${event.toolName} · Esc stop · Enter steer`);
    setTabTitle(ctx, event.toolName);
  });

  pi.on("tool_execution_end", async (_event, ctx) => {
    currentTool = "";
    ctx.ui.setStatus("run-control", "RUN · Esc stop · Enter steer");
    setTabTitle(ctx, "RUN");
  });

  pi.on("agent_settled", async (_event, ctx) => {
    running = false;
    currentTool = "";
    ctx.ui.setStatus("run-control", undefined);
    dirtyState = checkGitDirty();
    lastDirtyCheck = Date.now();
    setTabTitle(ctx, dirtyState ? "●" : "✓");
  });

  pi.on("turn_end", async (_event, ctx) => refreshSnapshot(ctx, true));
}

function installShell(pi: ExtensionAPI, ctx: ExtensionContext): void {
  if (!ctx.hasUI) return;
  installHeader(ctx);
  installEditor(pi, ctx);
  ctx.ui.setWorkingIndicator({
    frames: ["·π·", "∙π∙", "•π•", "✦π✦", "•π•", "∙π∙"].map((frame) => ctx.ui.theme.fg("accent", frame)),
    intervalMs: 180,
  });
  installFooter(ctx);
}

function installFooter(ctx: ExtensionContext): void {
  if (mode === "off") {
    ctx.ui.setFooter(undefined);
    return;
  }

  ctx.ui.setFooter((tui, theme, footerData) => {
    const unsubscribe = footerData.onBranchChange(() => tui.requestRender());
    return {
      dispose: unsubscribe,
      invalidate() {},
      render(width: number): string[] {
        const usage = ctx.getContextUsage();
        const usedPct = usage?.percent == null ? null : Math.max(0, Math.min(100, usage.percent));
        const gaugeWidth = width >= 100 ? 10 : width >= 70 ? 8 : 6;
        const gaugeColor = usedPct == null ? "muted" : usedPct >= 85 ? "error" : usedPct >= 70 ? "warning" : "success";
        const filled = usedPct == null ? 0 : Math.round(usedPct / 100 * gaugeWidth);
        const minor = theme.fg("dim", " · ");
        const major = theme.fg("dim", " │ ");
        const label = (text: string) => theme.fg("muted", text);
        const gauge = `${label("CTX")} ${theme.fg(gaugeColor, "█".repeat(filled))}${theme.fg("dim", "░".repeat(gaugeWidth - filled))} ${theme.fg(gaugeColor, usedPct == null ? "?" : `${Math.round(usedPct)}%`)}`;

        const statuses = [...footerData.getExtensionStatuses().values()].map(cleanStatus).filter(Boolean);
        latestStatuses = statuses;
        const statusText = statuses.slice(0, 5).map((status) => theme.fg(/error|fail|blocked/i.test(status) ? "error" : /run|work|pending/i.test(status) ? "warning" : "muted", truncateToWidth(status, 32, "…"))).join(minor);
        const goal = goalCache ? `${theme.fg("accent", "▌")} ${label("Goal:")} ${theme.fg("text", goalCache)}` : "";
        const branch = footerData.getGitBranch();
        const branchText = branch ? theme.fg(dirtyState ? "warning" : "border", `${branch}${dirtyState ? "*" : ""}`) : "";
        const model = theme.fg("customMessageLabel", ctx.model?.id ?? "no-model");
        const path = theme.fg("dim", formatCwd(ctx.cwd));
        const tokens = `${label("TOK")} ${theme.fg("text", `↑${formatTokens(tokCache.input)}`)}${minor}${theme.fg("accent", `↓${formatTokens(tokCache.output)}`)}`;
        const cost = `${label("COST")} ${theme.fg("syntaxNumber", `$${tokCache.cost.toFixed(3)}`)}`;
        const limits = cursorLimits ? `${label("CURSOR")} ${theme.fg("text", cursorLimits)}` : "";
        const agents = agentStatus.running || agentStatus.queued ? `${label("AGT")} ${theme.fg("customMessageLabel", `R${agentStatus.running}`)}${minor}${theme.fg("customMessageLabel", `Q${agentStatus.queued}`)}` : "";
        const stats = cachedStats ?? { webSearch: 0, webFetch: 0, webCache: 0, mcpCalls: 0, mcpErrors: 0 };
        const web = stats.webSearch || stats.webFetch ? `${label("WEB")} ${theme.fg("syntaxType", `S${stats.webSearch}`)}${minor}${theme.fg("syntaxType", `F${stats.webFetch}`)}${minor}${theme.fg("syntaxType", `C${stats.webCache}`)}` : "";
        const mcp = stats.mcpCalls || stats.mcpErrors ? `${label("MCP")} ${theme.fg("border", `Q${stats.mcpCalls}`)}${stats.mcpErrors ? minor + theme.fg("error", `E${stats.mcpErrors}`) : ""}` : "";
        const activity = currentTool ? theme.fg("warning", `◆ ${currentTool}`) : running ? theme.fg("accent", "◆ RUN") : "";

        if (mode === "minimal") {
          return [prioritizedLine([
            { text: activity, priority: 0 },
            { text: gauge, priority: 1 },
            { text: branchText, priority: 2 },
            { text: model, priority: 3 },
            { text: limits, priority: 4 },
            { text: tokens, priority: 5 },
          ], width, minor)];
        }

        if (mode === "compact" || mode === "balanced" || (mode === "detailed" && width < 64)) {
          const focus = prioritizedLine([
            { text: activity, priority: 0 },
            { text: goal, priority: 1 },
            { text: statusText, priority: 2 },
          ], width, minor);
          const telemetry = prioritizedLine([
            { text: branchText, priority: 2 },
            { text: model, priority: 3 },
            { text: gauge, priority: 0 },
            { text: limits, priority: 1 },
            { text: tokens, priority: 4 },
            { text: cost, priority: 5 },
          ], width, major);
          return [focus, telemetry].filter(Boolean);
        }

        const lines: string[] = [];
        if (goal || statusText || activity) lines.push(balanceLine(goal || activity, [goal && activity ? activity : "", statusText].filter(Boolean).join(minor), width));
        lines.push(balanceLine([path, branchText, model].filter(Boolean).join(minor), gauge, width));
        lines.push(...wrapGroups([tokens, cost, limits, agents, web, mcp], width, major));

        if (mode === "legacy") return lines;
        return lines.slice(0, width >= 90 ? 4 : 3);
      },
    };
  });
}
