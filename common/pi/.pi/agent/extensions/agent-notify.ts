// AI Agent 通知連携 (pi)
//
// pi のライフサイクルを tmux pane option (@agent_status) に反映し、
// 横断ビュー(prefix+a) / サイドバー(prefix+b) / ペーン枠アイコン / ウィンドウバッジに
// pi セッションを表示させる。Claude Code の hooks 配線と同等のことを pi extension で行う。
//
// 状態源スクリプト: ~/dotfiles/scripts/tmux-claude-pane.sh
// 仕様: ~/dotfiles/docs/specs/agent-stop-notification.md §4.1
//
// マッピング:
//   session_start    -> start      (running 化 + heartbeat)
//   tool_call        -> heartbeat   (実行中の生存信号。hang からの復帰も担う)
//   turn_end         -> set idle    (ターン終了=入力待ちで停止)
//   session_shutdown -> clear       (終了時に通知をクリア)

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const PANE = process.env.TMUX_PANE;
const SCRIPT = join(homedir(), "dotfiles", "scripts", "tmux-claude-pane.sh");

// tmux pane option を更新する。tmux 外では何もしない。fire-and-forget(非ブロッキング)。
function agent(...args: string[]): void {
  if (!PANE) return;
  execFile("bash", [SCRIPT, ...args], { env: process.env, timeout: 2000 }, () => {
    /* 失敗は致命的でないため無視 */
  });
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async () => agent("start"));
  pi.on("tool_call", async () => agent("heartbeat"));
  pi.on("turn_end", async () => agent("set", "idle"));
  pi.on("session_shutdown", async () => agent("clear"));
}
