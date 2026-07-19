# Agent状態管理 改善計画（完了）

現行仕様は[AI agent状態管理](specs/agent-stop-notification.md)へ移行した。

## 目的

Claude Code、pi、Codex、Gemini CLI、Cursor Agent、Command Code の状態を tmux pane option に集約し、`prefix+a` と `prefix+b` が同じ最新状態を表示する。

## 方針

1. `scripts/tmux-claude-pane.sh` を状態の正本として維持する。
2. provider hook は `running` 開始、進捗heartbeat、`idle`/`permission`/`error` 終了だけを通知する。
3. event heartbeatを持つproviderでは端末再描画を生存判定に使わない。画面監視はhook不足providerのfallbackに限定する。
4. 状態遷移時にindexを無効化し、consumerが最新snapshotを再生成する。heartbeatだけでは無効化しない。
5. hang確定直前にpane状態を再確認し、heartbeatとの競合を防ぐ。
6. isolated tmux socketで状態遷移、hang、cache fallbackを検証する。

## Provider対応

| Provider | start | heartbeat | stop | 制約 |
| --- | --- | --- | --- | --- |
| Claude Code | UserPromptSubmit | Pre/PostToolUse | Stop / StopFailure | PermissionRequestあり |
| pi | agent_start | message/tool progress（間引き） | agent_settled | extension内更新を直列化 |
| Codex | UserPromptSubmit | Pre/PostToolUse | PermissionRequest / Stop | 初回hook trust確認あり。legacy notifyはidle fallback |
| Gemini CLI | BeforeAgent | Before/AfterTool | AfterAgent | hooksは同期実行 |
| Cursor Agent | beforeSubmitPrompt | shell/edit等のhook | stop | 公開hook範囲内でbest effort |
| Command Code | prompt開始相当なし | Pre/PostToolUse | Stop | SessionStartはidle初期化のみ |

## 完了条件

- 状態更新順序が保証される。
- 静止したevent heartbeat paneが1回の閾値超過でhangになる。
- piのspinnerだけではhangが解除されない。
- `prefix+a` rescanとsidebarが更新済みindexを読む。
- cache障害時に直接tmux scanへfallbackする。
- shell構文、TypeScript、isolated tmuxテスト、markdown link、package duplication検査が成功する。
