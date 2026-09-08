// Pi UI shell: one owner for header, composer, footer, working indicator, and tab title.
// Shows the same essential session information at every terminal width.

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
  wrapTextWithAnsi,
  type Focusable,
} from "@earendil-works/pi-tui";
import { execSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";

type DisplayMode = "off" | "on";
type EditorFactory = NonNullable<ReturnType<ExtensionContext["ui"]["getEditorComponent"]>>;
type ShellEditorFactory = EditorFactory & { __piUiShell?: true };

const MODE_FILE = join(homedir(), ".pi", "agent", "statusline-mode");
const DIRTY_CHECK_INTERVAL_MS = 5000;
const HIDDEN_STATUSES = new Set(["pi-permission-system", "ponytail", "extmgr"]);

function loadMode(): DisplayMode {
  try {
    return readFileSync(MODE_FILE, "utf-8").trim() === "off" ? "off" : "on";
  } catch { return "on"; }
}

function saveMode(value: DisplayMode): void {
  try { writeFileSync(MODE_FILE, value); } catch { /* non-fatal */ }
}

let mode = loadMode();
let dirtyState = false;
let lastDirtyCheck = 0;
let currentTool = "";
let running = false;
let latestStatuses: string[] = [];
let agentStatus = { running: 0, queued: 0 };

function checkGitDirty(): boolean {
  try {
    return execSync("git status --porcelain", {
      encoding: "utf-8",
      timeout: 1000,
      stdio: ["pipe", "pipe", "ignore"],
    }).trim().length > 0;
  } catch { return false; }
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

function refreshSnapshot(): void {
  refreshAgents();
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
  return usage?.percent === null || usage?.percent === undefined ? "?" : `${Math.round(usage.percent)}%`;
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
      return [first, truncateToWidth(` ${theme.fg("dim", "╰─")} ${meta}`, width)];
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
      const topRight = theme.fg("dim", ` THINK ${pi.getThinkingLevel()} `);
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

  invalidate(): void {}

  render(): string[] {
    const inner = this.width - 2;
    const border = (text: string) => this.theme.fg("border", text);
    const row = (text = "") => {
      const clipped = truncateToWidth(` ${text}`, inner);
      return border("│") + clipped + " ".repeat(Math.max(0, inner - visibleWidth(clipped))) + border("│");
    };
    const output = [
      border(`╭${"─".repeat(inner)}╮`),
      row(`${this.theme.bold(this.theme.fg("accent", "π  SESSION STATUS"))}  ${this.theme.fg("dim", `footer: ${mode}`)}`),
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
    description: "Show or hide the session footer: on, off",
    getArgumentCompletions: () => [
      { value: "on", label: "Show session information" },
      { value: "off", label: "Hide the footer" },
    ],
    handler: async (args, ctx) => {
      const requested = args.trim();
      if (requested === "on" || requested === "off") mode = requested;
      else if (["minimal", "compact", "balanced", "detailed", "legacy"].includes(requested)) mode = "on";
      else if (!requested) mode = mode === "off" ? "on" : "off";
      else {
        ctx.ui.notify("Usage: /statusline on|off", "warning");
        return;
      }
      saveMode(mode);
      installFooter(ctx);
      ctx.ui.notify(`Statusline: ${mode}`, "info");
    },
  });

  pi.registerCommand("status", {
    description: "Show Pi session information",
    handler: async (_args, ctx) => {
      refreshSnapshot();
      const usage = ctx.getContextUsage();
      await ctx.ui.custom<void>(
        (_tui, theme, _keybindings, done) => new StatusOverlay(theme, [
          ["PROJECT", `${formatCwd(ctx.cwd)}${dirtyState ? "  *dirty" : ""}`],
          ["MODEL", `${ctx.model?.provider ?? "—"}/${ctx.model?.id ?? "—"} · THINK ${pi.getThinkingLevel()}`],
          ["CONTEXT", usage?.percent == null ? "unknown" : `${usage.percent.toFixed(1)}% / ${formatTokens(usage.contextWindow ?? 0)}`],
          ["AGENTS", `running ${agentStatus.running} · queued ${agentStatus.queued}`],
          ["STATUS", latestStatuses.join(" · ")],
        ], () => done()),
        { overlay: true },
      );
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    refreshSnapshot();
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

  pi.on("turn_end", async () => refreshSnapshot());
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
  ctx.ui.setFooter((tui, theme, footerData) => {
    const unsubscribe = footerData.onBranchChange(() => tui.requestRender());
    return {
      dispose: unsubscribe,
      invalidate() {},
      render(width: number): string[] {
        latestStatuses = [...footerData.getExtensionStatuses()]
          .filter(([key]) => !HIDDEN_STATUSES.has(key))
          .map(([, value]) => cleanStatus(value)).filter(Boolean);
        if (mode === "off" || width <= 0) return [];

        const usage = ctx.getContextUsage();
        const usedPct = usage?.percent == null ? null : Math.max(0, Math.min(100, usage.percent));
        const gaugeWidth = 8;
        const gaugeColor = usedPct == null ? "muted" : usedPct >= 85 ? "error" : usedPct >= 70 ? "warning" : "success";
        const filled = usedPct == null ? 0 : Math.round(usedPct / 100 * gaugeWidth);
        const minor = theme.fg("dim", " · ");
        const gauge = `${theme.fg(gaugeColor, "█".repeat(filled))}${theme.fg("dim", "░".repeat(gaugeWidth - filled))} ${theme.fg(gaugeColor, usedPct == null ? "?" : `${Math.round(usedPct)}%`)}`;

        const statusText = latestStatuses.map((status) => theme.fg(/error|fail|blocked/i.test(status) ? "error" : /run|work|pending/i.test(status) ? "warning" : "muted", status)).join(minor);
        const branch = footerData.getGitBranch();
        const branchText = branch ? theme.fg(dirtyState ? "warning" : "border", `${branch}${dirtyState ? "*" : ""}`) : "";
        const model = theme.fg("customMessageLabel", ctx.model?.id ?? "no-model");
        const path = theme.fg("dim", formatCwd(ctx.cwd));
        return [statusText, [path, branchText, model, gauge].filter(Boolean).join(minor)]
          .filter(Boolean)
          .flatMap((line) => wrapTextWithAnsi(line, width))
          .map((line) => truncateToWidth(line, width, ""));
      },
    };
  });
}
