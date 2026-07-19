// pi lifecycle → tmux agent state.
// agent_start/agent_settled represent the whole run; message/tool updates are throttled heartbeats.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const PANE = process.env.TMUX_PANE;
const SCRIPT = join(homedir(), "dotfiles", "scripts", "tmux-claude-pane.sh");
const HEARTBEAT_INTERVAL_MS = 5_000;

export default function (pi: ExtensionAPI) {
  let queue = Promise.resolve();
  let lastHeartbeat = 0;
  let lastRunErrored = false;

  function update(...args: string[]): Promise<void> {
    if (!PANE) return queue;
    queue = queue.then(
      () =>
        new Promise<void>((resolve) => {
          execFile("bash", [SCRIPT, ...args], { env: process.env, timeout: 2_000 }, () => resolve());
        }),
    );
    return queue;
  }

  function heartbeat(force = false): Promise<void> {
    const now = Date.now();
    if (!force && now - lastHeartbeat < HEARTBEAT_INTERVAL_MS) return queue;
    lastHeartbeat = now;
    return update("heartbeat", "pi", "event");
  }

  pi.events.on("agent-notify:permission", (data: unknown) => {
    if (typeof data !== "boolean") return;
    void (data ? update("set", "permission", "pi") : heartbeat(true));
  });

  pi.on("session_start", () => update("set", "idle", "pi"));
  pi.on("agent_start", () => {
    lastRunErrored = false;
    lastHeartbeat = Date.now();
    return update("start", "pi", "event");
  });
  pi.on("message_update", () => heartbeat());
  pi.on("tool_execution_start", () => heartbeat());
  pi.on("tool_execution_update", () => heartbeat());
  pi.on("tool_execution_end", () => heartbeat());
  pi.on("agent_end", (event) => {
    const lastAssistant = [...event.messages]
      .reverse()
      .find((message) => message.role === "assistant") as { stopReason?: string } | undefined;
    lastRunErrored = lastAssistant?.stopReason === "error";
  });
  pi.on("agent_settled", () => update("set", lastRunErrored ? "error" : "idle", "pi"));
  pi.on("session_shutdown", () => update("clear"));
}
