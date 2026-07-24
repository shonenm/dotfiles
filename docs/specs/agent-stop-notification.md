# AI agent状態管理

Claude Code、pi、Codex、Gemini CLI、Cursor Agent、Command Code の実行状態をtmuxへ集約する現行仕様。

## 状態の正本

ローカルagentの正本はpane user optionであり、`scripts/tmux-claude-pane.sh`だけが更新する。

| option | 内容 |
| --- | --- |
| `@agent_status` | `running` / `idle` / `permission` / `complete` / `hang` / `error` |
| `@agent_provider` | `claude` / `pi` / `codex` / `gemini` / `cursor` / `cmd` |
| `@agent_state_since` | 現状態へ遷移したUnix時刻 |
| `@agent_heartbeat` | 最後に実イベントまたは画面変化を観測したUnix時刻 |
| `@agent_heartbeat_source` | `event`または`screen` |
| `@agent_outhash` | `screen` fallback用の末尾5行hash |

`complete`は後方互換用に受理するが、通常のturn完了は`idle`へ正規化する。SlackやSketchyBarの`complete`通知とは分離する。

## Provider adapter

| Provider | running | activity | waiting / stop | error / clear |
| --- | --- | --- | --- | --- |
| Claude Code | `UserPromptSubmit` | `PreToolUse`、`PostToolUse`、`PostToolUseFailure` | `PermissionRequest`、`Stop` | `StopFailure`、`SessionEnd` |
| pi | `agent_start` | `message_update`、tool execution events（5秒間引き） | `agent_settled` | assistant `stopReason`、`session_shutdown` |
| Codex | `UserPromptSubmit` | `PreToolUse`、`PostToolUse` | `PermissionRequest`、`Stop` | legacy `notify`はidle fallback |
| Gemini CLI | `BeforeAgent` | `BeforeTool`、`AfterTool` | `AfterAgent` | `SessionEnd` |
| Cursor Agent | `beforeSubmitPrompt` | shell/read/edit/thought hooks | `stop` | CLI hook APIの範囲でbest effort |
| Command Code | 最初の`PreToolUse` | `PreToolUse`、`PostToolUse` | `Stop` | prompt開始eventがないためtext-only turnのrunningは取得不可 |

Provider hookはpane state更新を同期完了してから戻る。pi extensionはPromise queueで更新順を保証する。Codexは初回起動時にhook trust確認が表示されるため、内容を確認して許可する。

## Hang判定

`tmux-agent-hang-watch.sh`が15秒ごとに`hang-scan`を実行し、既定120秒進捗がない`running` paneを`hang`へ遷移する。

- `event`: hook heartbeatだけを使用する。TUI spinnerや再描画は生存扱いにしない。
- `screen`: eventを提供できない経路のfallback。末尾5行が変化した場合だけheartbeatを更新する。
- hang確定直前にstatusとheartbeatを再読込し、同時到着したactivityを上書きしない。
- `hang`または`permission`中に`heartbeat`が再開すれば`running`へ復帰する。`idle`後の遅延heartbeatは無視する。

`hang`は進捗停止の推定であり、process deathの断定ではない。

## IndexとUI

`tmux-agent-index.sh`はtmux socketごとのruntime directoryへpane/session snapshotを保存する。refreshとinvalidateは同じlockで直列化し、状態遷移後の次のconsumer読込で即refreshする。cacheが利用不能ならconsumerは直接`tmux list-*`へfallbackする。

- `prefix+a`: read-only `capture-pane` previewとpane jump。実paneの`swap-pane`は行わない。
- `prefix+A`: 同じindexを3秒周期で描画するsidebar。
- `prefix+R`: 現tmux serverのwatcher再起動、hang scan、index refresh。

runtime namespaceは`${TMUX%%,*}`のchecksumを用いるため、複数tmux server間でcache/PIDを共有しない。

## Remote / container

remote状態は`${DOTFILES_SHARED_DIR:-$HOME/.cache}/claude/status/`へatomic publishする。JSONには`tool`、`status`、`workspace`、`tmux_session`、`tmux_window_index`、`updated`を含む。consumerはprovider/workspaceごとの最新recordをstatus filterより先に確定し、`none`をtombstoneとして扱う。

## 検証

```bash
scripts/test-tmux-agent-status.sh
shellcheck -S warning -x scripts/tmux-agent-*.sh scripts/tmux-claude-pane.sh scripts/ai-notify.sh
scripts/check-markdown-links.py
scripts/check-package-duplication.sh
```

テストは隔離tmux socketを使用し、通常のtmux serverやruntime cacheを操作しない。
