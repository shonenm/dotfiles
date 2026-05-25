// Remote Control Extension for pi
//
// /remote — show RPC/tmux connection info for accessing this session remotely.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("remote", {
    description: "Show remote access info for this session",
    handler: async (_args, ctx) => {
      const parts: string[] = [];

      // Session file for resume
      const sessionFile = ctx.sessionManager.getSessionFile();
      if (sessionFile) {
        parts.push(`Session: ${sessionFile}`);
      }

      // tmux info
      try {
        const tmux = execSync("tmux display-message -p '#S:#I.#P'", {
          encoding: "utf-8", timeout: 2000,
          stdio: ["pipe", "pipe", "ignore"],
        }).trim();
        const host = execSync("hostname", {
          encoding: "utf-8", timeout: 2000,
          stdio: ["pipe", "pipe", "ignore"],
        }).trim();

        parts.push(`tmux: ${host}:${tmux}`);
        parts.push("");
        parts.push("Remote access:");
        parts.push(`  ssh ${host} -t 'tmux attach -t ${tmux.split(":")[0]}'`);
      } catch {
        // not in tmux
      }

      // RPC mode hint
      parts.push("");
      parts.push("RPC mode: pi --mode rpc --session <file>");

      ctx.ui.notify(parts.join("\n"), "info");
    },
  });
}
