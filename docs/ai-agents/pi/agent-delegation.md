# pi Agent Delegation Layer

> **由来:** **Upstream** pi・pueue / **Plugin** pi-subagents / **Configuration** agent定義・model tier / **Custom** agent-delegation拡張（[区分](../../provenance.md#区分)）

利用者が明示的にopt-inした場合だけ使うサブエージェント委譲の仕組み。pi-subagents（コミュニティ） + agent-delegation.ts（カスタム）の2層構成。通常実装の品質向上を理由に自動起動せず、reviewは原則1 passとする。

## Architecture

```
親セッション (pi)
  ├─ subagent (pi-subagents)        ← chain/parallel + TUI進捗
  │   └─ reviewer / scout / worker / oracle
  └─ delegate_agent (custom)        ← pueue非同期 + 自動モデル選択
      └─ pueue queue → inactivity watchdog → pi --mode json -p → 結果回収
```

## Tools

### pi-subagents (community)

| Tool | 用途 |
|------|------|
| `subagent` | 単一/チェーン/並列実行。TUI進捗表示付き |

自然言語で委譲可能:
```
"Use reviewer to audit auth module for security issues"
"Use scout to explore how the payment flow works"
"Run parallel reviewers: one for correctness, one for tests"
```

### agent-delegation.ts (custom)

| Tool | 用途 |
|------|------|
| `delegate_agent` | sync/async (pueue) サブエージェント起動。難易度自動モデル選択 |
| `check_delegation` | pueue タスク状態確認 |
| `wait_delegation` | タスク完了待ち + 結果取得 |

## Built-in Agent Roles

| ロール | 用途 | 推奨難易度 | モデル |
|--------|------|:--:|--------|
| `reviewer` | コードレビュー、セキュリティ監査、品質チェック | high | `subagents.defaultModel` |
| `scout` | コードベース探索、read-only調査、依存関係分析 | medium | `subagents.defaultModel` |
| `worker` | 承認済み計画からの実装 | medium | `subagents.defaultModel` |
| `oracle` | セカンドオピニオン、設計レビュー、前提検証 | high | `subagents.defaultModel` |

`pi-subagents` の既定モデルは `settings.json` の `subagents.defaultModel` に設定した `openai-codex/gpt-5.6-luna`。通常の呼び出しでは `model` を渡さない。`defaultThinking` は、agent定義にthinkingがない場合の既定値として `medium` を設定する。`modelScope.allow` はこのモデル、`openai-codex/gpt-5.6-sol`、`openai-codex/gpt-6-astra` を許可し、利用者が明示した場合だけ呼び出し時にモデルを上書きする。

`modelScope.allow` と `enabledModels` はモデルを登録する設定ではない。既定モデルは現在のregistryに存在する完全修飾名（`provider/model`）で設定し、`subagent` の `action: "list", capabilities: true` と `model` なしの起動で確認する。registryへの登録だけでは、現在の認証で利用できる保証はない。モデル指定なしの子起動で実際の応答まで検証する。`openai-codex/gpt-5.4-mini` はChatGPTアカウントでの起動時に非対応エラーとなったため、既定値には使用しない。

`pi-dynamic-workflows` のモデル割り当ては別設定の `~/.pi/workflows/model-tiers.json` で管理する。`pi-subagents` の許可リスト変更では更新しない。

## Model Auto-Selection

`delegate_agent` は difficulty に応じて自動的にモデルを選択する:

| Difficulty | Primary Model | Override |
|:----------:|---------------|----------|
| `high` | openai-codex/gpt-5.6-sol:high | 手動オーバーライド |
| `medium` | openai-codex/gpt-5.4-mini:medium | 手動オーバーライド |
| `low` | openai-codex/gpt-5.3-codex-spark:off | 手動オーバーライド |

モデルは手動オーバーライド可能。

## Execution Modes

| Mode | 動作 | 用途 |
|------|------|------|
| **async** (default) | pueue でバックグラウンド実行。`check_delegation` + `wait_delegation` で結果回収 | 独立タスクの並列化 |
| **sync** | pueueへ登録後、最大10分待機。完了時は結果を返し、timeout時は継続中のtask IDを返す | 依存関係のある逐次タスク |

## pueue Integration

非同期実行には pueue デーモンが必要:

```bash
pueued -d        # デーモン起動
pueue status     # 状態確認
pueue log <id>   # ログ確認
pueue wait <id>  # 完了待ち
```

セッション開始時に自動でデーモン起動を試みる。sync/asyncとも必ずpueueへ登録するため、親側の待機がtimeoutしても子taskはtask IDで追跡できる。timeout時は同じtask IDを`wait_delegation`へ渡して再待機し、同じworktreeへ代替writerを起動しない。

`pi -p`はpipeから受け取った標準入力をEOFまでpromptへ追加する。pueueは`pueue send`用にtaskの標準入力pipeを保持するため、委譲時は標準入力を`/dev/null`へ明示的に接続する。この接続を外すと、model呼び出し前にtaskが無期限に待機し、pueue log、session artifact、worktree変更がすべて空のままになる。watchdog導入後も、pueueが起動する`sh -c 'exec "$@" </dev/null'`を通してwrapperとPiの両方へEOFを渡す。

切り分けでは、同じ最小promptをpueue直下と`</dev/null`付きで実行する。前者だけが停止する場合はprovider障害ではなく標準入力のEOF待ちである。model/provider単体は、pueueを介さず`pi --no-session --no-extensions --no-skills -p 'Reply only OK.'`で別に確認する。

## Inactivity Watchdog

観測した根本原因は、plain `pi -p`が最終応答までstdoutへ進捗を出さず、pueue metadataにも最後の進捗時刻がないため、開始済みの停止taskと正常な長時間taskを区別できないことだった。委譲task内のNode wrapperがPiを`--mode json`で起動し、JSONLを逐次parseして監視する。wrapperはpueueがtaskを実際に開始した後で起動するため、queue待ち時間はinactivityに含まれない。child spawn直後から最初のeventまでのsilenceもstartup silenceとして同じdeadlineで監視する。

activityはparseに成功したPi JSON recordの次のeventだけとする。

- `agent_start` / `agent_end`
- `message_update`
- `tool_execution_start` / `tool_execution_update` / `tool_execution_end`

model streamingとtool eventのたびにdeadlineをresetする。wall-clock runtime、CPU、file変更、plain text、parse不能な行、session headerはactivityにしない。`message_end`はauthoritativeな最終assistant textの回収に使うが、deadlineの延長には使わない。

固定thresholdは**10分**。foreground command capの5分をそのまま閾値にすると、`tool_execution_start`後に上限まで出力しない正当なtoolとprovider側の遅延が競合するため、2倍の余裕を取る。具体的な別use caseがないため設定項目は設けない。

10分間activityがない場合、wrapperはPiを独立process groupごと`SIGTERM`し、5秒待ってprocess groupが残存する場合だけ`SIGKILL`へescalateする。direct Pi childが先に終了してもgroup livenessを確認し、tool subprocessが残っている間はgraceとescalationを取り消さない。group消滅を確認してからwrapperはexit 124で終了し、pueueにはfailureとして残す。外部からwrapperへ届いた終了signalもchild process groupへ転送する。promptはargvのままでshell source、watchdog state、diagnosticへ複製しない。正常終了時は最後のassistant `message_end`のtextを通常のpueue logへ出す。

`check_delegation(taskId)`と`wait_delegation(taskId)`は`PI_DELEGATION_INACTIVITY` markerを検出し、startup silenceか最後に観測したeventを含むdiagnosticを表示する。発生時は同じtask IDのpueue logで最後のeventとSIGKILL escalation有無を確認し、providerまたは停止したtoolを修復してから新しい委譲を起動する。taskがまだrunningの場合は代替writerを起動せず、同じIDを追跡する。

## Audit

全委譲は `~/.pi/research/delegation.jsonl` に記録:

```json
{"timestamp":"2026-05-24T...","difficulty":"high","task":"review auth module","taskId":"0"}
```

## pi-subagents vs agent-delegation.ts

| | pi-subagents | agent-delegation.ts |
|---|---|---|
| **chain/parallel** | ✅ | ❌ |
| **TUI 進捗表示** | ✅ chain visualization | ❌ |
| **pueue 非同期** | ❌ | ✅ |
| **自動モデル選択** | ❌ | ✅ difficulty tiers |
| **audit log** | ❌ | ✅ delegation.jsonl |
| **check/wait** | ❌ | ✅ |
| **自然言語委譲** | ✅ | ✅ |
| **インストール** | `pi install npm:pi-subagents` | dotfiles 内蔵 |

両方を用途別に利用可能にするが、自動選択はしない。reviewerの提案は元のacceptance criteriaを拡張せず、再reviewは利用者が明示した場合だけ行う。

## Extensions

| Extension | 役割 |
|-----------|------|
| `agent-delegation.ts` | pueue非同期実行 + 自動モデル選択 |
| `pi-subagents` (package) | chain/parallel実行 + TUI表示 |

## Skills

| Skill | 用途 |
|-------|------|
| `github-delegate` | 委譲ワークフローガイドライン |

## 使用例

```
# コードレビュー（非同期）
delegate_agent(task: "Use reviewer to audit src/auth/ for security issues", difficulty: "high")

# 並列レビュー
delegate_agent(task: "Review for correctness", difficulty: "high")
delegate_agent(task: "Review for performance", difficulty: "high")

# 結果確認
check_delegation()
wait_delegation(taskId: "0")
```
