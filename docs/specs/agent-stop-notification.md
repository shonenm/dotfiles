# Agent Stop Notification Specification

エージェント（Claude Code / Codex / Cursor / Command Code / pi）の「処理が止まった」状態を
視覚的に通知する仕組みの要件。tmux ペーン/ウィンドウを第一級の通知面とする。

> Status: 方針確定（完全自作 = §10.3 A）。実装フェーズへ移行。未決事項は §9。
> 上位仕様は [agent-infrastructure.md](./agent-infrastructure.md) の "Completion Notify" を本仕様で置き換え・詳細化する。

## 1. 背景と問題（現状の不完全さ）

現状は通知面・スクリプトが複数あり、配線がツールごとにバラバラで一貫しない。

| 問題 | 内容 |
|------|------|
| 二系統未統合 | ペーンアイコン (`tmux-claude-pane.sh`) は Command Code からしか呼ばれず、Claude/Codex/Cursor は呼ばない。Claude はペーン単位表示が出ない |
| クリア未配線 | Command Code も `Stop`・ターン開始(`UserPromptSubmit`) でのペーン状態クリアが無い → 残留する |
| ハング非検知 | プロセスが固まり出力も停止した「真のスタック」は `Stop`/`idle` が来ず、どの面にも出ない |
| 横断不可視 | 「今どのペーン/ウィンドウ/ホストが止まっているか」を一覧する集約ビューが無い |
| 状態残留・誤消去 | focus 5秒タイマー、stale 3600s、`scan` のペーン文字列 grep ヒューリスティックが壊れやすく、消えない/誤って消える |
| complete と idle の混同 | 「完了」と「入力待ちで停止」が区別されず、`complete` は mention 無し＋10秒自動消去で見逃しやすい |

## 2. スコープ

- 対象状態: `idle`（入力待ち）/ `permission`（承認待ち）/ `complete`（ターン正常終了）/ `hang`（無応答）/ `error`
- 第一優先通知面: tmux ペーンアイコン・tmux ウィンドウバッジ
- 第二: 集約ビュー（横断一覧）、SketchyBar、Slack（既存維持）
- 全対応ツールで振る舞いを統一（spec 共有・ネイティブ実装、symlink しない）

## 3. 状態モデル（Single Source of Truth）

エージェント1セッション = tmux 1ペーンに対し、唯一の状態を持つ。

### 3.1 状態

| 状態 | 意味 | 要対応度 |
|------|------|:--:|
| `running` | ターン実行中（`UserPromptSubmit`〜終了の間） | — |
| `permission` | ツール実行の承認待ちで停止 | 高（即対応） |
| `hang` | `running` のまま無応答（推定スタック） | 高 |
| `error` | エラー終了 | 高 |
| `idle` | 入力待ちで停止 | 中 |
| `complete` | ターン正常終了 | 低（確認のみ） |
| `none` | 通知なし（未起動 / 確認済み / クリア済み） | — |

### 3.2 表示優先度（1ペーンが複数該当しない前提だが、ウィンドウ集約時の優先順）

`permission` > `hang` > `error` > `idle` > `complete` > `running` > `none`

### 3.3 Canonical store

- 正本は tmux pane user option `@agent_status`（および `@agent_icon`）とする。
  - 理由: pane と寿命が一致 → ペーン消滅で状態も自動消滅し、残留しない。`scan` ヒューリスティックを廃止できる。
- ウィンドウバッジ・SketchyBar・横断ビューはすべて pane option の集約から導出する（派生ビュー）。
- リモート/コンテナはローカルに tmux pane が無いため、ファイルベース (`/tmp/claude/status` 相当) を補助 store として維持し、ローカルの watcher が取り込む（4.4）。

## 4. 状態遷移

### 4.1 トリガー（hook イベント → 状態）

| イベント | 遷移 | 備考 |
|---------|------|------|
| `UserPromptSubmit` | `*` → `running` | 新ターン開始＝ユーザーが対応した。既存通知をクリア |
| `PreToolUse` / `PostToolUse` | `running` 維持 + heartbeat 更新 | ハング検知の生存信号（4.3） |
| `Notification[permission_prompt]` | → `permission` | |
| `Notification[idle_prompt]` | → `idle` | |
| `Stop` | → `complete` | |
| エラー終了（ツール固有） | → `error` | |
| watcher 判定 | `running` → `hang` | 4.3 |

全ツールでこの対応表を統一配線する。現状欠けている配線:
- Claude/Codex/Cursor: ペーンアイコンの set（全状態）と `UserPromptSubmit` でのクリア
- Command Code: `Stop`（complete）と `UserPromptSubmit` クリア

> 重要（idle 検知の信頼性）: Claude Code の `Notification[idle_prompt]` は仕様上ハードコード 60秒経過後に発火し、かつ「全応答後に発火して使い物にならない」との報告がある（CC issue #12048 / #13922 / #13024）。「ターンが止まった瞬間の入力待ち」を取りたい本要件には不適。`Stop`（complete）を即時の「停止」シグナルとして主に使い、純粋な `idle` 表示は idle_prompt に依存しすぎない設計とする。代替状態源は §10.2 を参照。

### 4.2 クリア（消去）ポリシー

| 契機 | 動作 | 対象状態 |
|------|------|---------|
| `UserPromptSubmit`（新ターン） | 即クリア → `running` | 全状態 |
| ペーン消滅 | 状態も消滅（pane option 特性） | 全状態 |

誤消去防止のため `$TMUX_PANE` 固定で対象ペーンを特定（現行実装を踏襲）。

> フォーカス到達クリア・時間減衰クリアの是非は要件未確定。現行実装には complete の10秒自動消去・focus 5秒タイマーが存在するが、本仕様では方針を確定しない（§9 で決定）。

### 4.3 ハング検知

`running` のまま実際に固まったケースを検知する。

- heartbeat: `UserPromptSubmit` / `PreToolUse` / `PostToolUse` で pane option `@agent_heartbeat`（epoch秒）を更新。
- watcher: 既存の tmux status 更新サイクル（数秒間隔）または軽量デーモンが、`running` かつ `now - heartbeat > HANG_THRESHOLD` のペーンを `hang` 表示にする。
- 誤検知対策（重要）: 長時間 Bash（ビルド/テスト）は `PostToolUse` まで heartbeat が来ず正常に「実行中」。これを `hang` と誤判定しないため:
  - `HANG_THRESHOLD` を十分大きく（暫定 120s、要調整）。
  - 補助シグナルとしてペーン出力の変化（`capture-pane` 末尾のハッシュ差分）を併用 — 出力が動いていれば生存とみなす。
- `hang` は「推定」表示であり、復帰（出力再開 / `PostToolUse` / `Stop`）で自動的に正しい状態へ戻る。

> 決定事項（要確認）: ハング検知を「全 running ペーン対象」にするか「ユーザーが明示登録したペーンのみ」か。誤検知許容度に依存。

### 4.4 リモート / コンテナ

- リモート側 hook はファイル (`/tmp/claude/status/workspace_*.json`) に状態を書き、ローカル watcher（inotifywait over SSH / launchd）が取り込む（現行踏襲）。
- 取り込んだ状態は、対応する tmux ペーン（ローカルに SSH/コンテナ接続している面）の pane option に反映する。マッピングは `workspace_map.json`（beacon 登録）を使う。
- リモートはハング検知の heartbeat も同経路で転送する。

## 5. 視覚表現要件

### 5.1 ペーン（最優先）

- 各ペーンの status line / border / title に状態アイコンを表示。
- アイコンは状態別に区別（現行: idle `󰔟` / permission `󰌆` / complete ``。`hang`・`error` 用を追加）。
- 色は要対応度に連動（permission/hang/error = 警告色、idle = 注意色、complete = 控えめ）。

### 5.2 ウィンドウバッジ

- ウィンドウ内ペーンの状態を集約し、最高優先度の状態と「停止ペーン数」を数字付きバッジで表示。
- 派生ビューなので pane option 集約から都度算出（キャッシュ可、TTL 短め）。

### 5.3 横断集約ビュー（新規・主要要件）

「今どこが止まっているか」を1画面で見るための一覧。

- 全 tmux session / window / pane（＋リモート取り込み分）を走査し、`none`/`running` 以外を一覧。
- 表示項目: 状態 / プロジェクト / session:window / ホスト（local/remote 名）/ 経過時間。
- 要対応度順にソート。選択で該当ペーンへジャンプ（tmux switch-client / select-window）。
- 提供形態: コマンド（例 `agent-status` 系）＋ tmux popup キーバインド。

### 5.4 SketchyBar / Slack

- 既存の派生ビューとして維持。pane option 集約 → SketchyBar、要対応状態 → Slack mention（現行の mention 制御を踏襲）。
- `complete` は mention 無し（後で確認）、`permission`/`idle`/`hang`/`error` は mention あり。

## 6. 信頼性・非機能要件

- 残留しない: ペーン消滅・新ターンで確実にクリア。ファイルベース store は GC（stale 閾値）で補完。
- 誤消去しない: `$TMUX_PANE` 固定、要対応状態はフォーカス/時間で消さない。
- 重複抑制: 同一ペーン・同一状態の短時間連続更新を抑制（現行2秒踏襲）。
- 競合耐性: pane option はアトミック。ファイル store は一時ファイル + mv。
- 低オーバーヘッド: シェル起動・status 更新サイクルに影響を与えない。watcher は軽量・遅延ロード。
- ヒューリスティック廃止: `scan` のペーン文字列 grep は hook 駆動 + heartbeat に置換（ツール起動時の取りこぼし救済が必要なら最小限の初期スキャンのみ）。

### 6.1 パフォーマンス設計メモ（実測ベース）

| 箇所 | コスト | 対策 |
|------|--------|------|
| heartbeat hook | 1回 ~27ms(fork+tmux)。tool 毎に発火 | `PostToolUse` のみに限定(`PreToolUse` 廃止)。長 tool の生存は watcher の出力ハッシュ差分で担保し heartbeat 冗長分を削減 |
| file store | `set_status` が timestamp 付きファイルを書き続け無限蓄積 → scan が全件 jq | workspace ごと旧ファイルを削除し1ファイルに(get は最新のみ参照) |
| サイドバー render | 128ms/3s → ファイル数分 jq spawn + agent毎 subshell | 全ファイルを単一 `jq -s` で処理、rank+glyph を1関数化。実測 128ms→34ms |
| 横断ビュー popup | ~130ms/回 | on-demand(prefix+a / ^R)なので許容 |
| hang watcher | 15s 周期、running ペーンのみ capture-pane | 低頻度・対象限定で軽量 |
| window バッジ | status 更新(~5s)毎、3s キャッシュ + pane option 優先 | file store 1ファイル化で fallback も軽量 |

原則: 常駐ループ(サイドバー/watcher)は jq/subprocess を最小化し、無制限に増える状態(file store)は書き込み側で必ず上限を設ける。

## 7. 現行コンポーネントの扱い

| 現行 | 変更方針 |
|------|---------|
| `ai-notify.sh` | Slack/SketchyBar 派生ビューとして維持。状態源は pane option に一本化 |
| `tmux-claude-pane.sh` | 正本 store の更新・クリアの中核に昇格。`scan` 廃止/縮小、`hang` 追加、heartbeat 対応。多ツール対応で `claude` → `agent` リネーム検討 |
| `tmux-claude-focus.sh` | フォーカスクリアの是非は §9 で確定後に方針決定 |
| `tmux-claude-badge.sh` | pane option 集約から算出する派生ビューに変更 |
| `claude-status.sh` | リモート/コンテナ取り込みとファイル store GC に役割を限定 |
| hooks 配線（各 `*-settings`） | 4.1 の対応表で全ツール統一。欠けている配線を追加 |

## 8. 受け入れ基準（E2E）

実使用シナリオで以下を確認してから完了とする（単体テスト不可）。

1. Claude のペーンで承認待ち → 当該ペーンに permission アイコン、ウィンドウバッジ点灯、Slack mention。
2. 別ウィンドウ作業中に他ペーンが idle/complete → 横断ビューで一覧でき、ジャンプできる。
3. 該当ペーンで新たな指示を入力（`UserPromptSubmit`）→ 通知が即クリア。
4. 長時間ビルド中（正常）に `hang` 誤検知しない。実際に固めた場合 `HANG_THRESHOLD` 後に `hang` 表示、出力再開で復帰。
5. ペーンを閉じる → 状態が残留しない。
6. リモートホストの停止状態がローカル tmux に反映される。
7. Claude/Codex/Cursor/Command Code すべてで 1〜3 が同一に動作。

## 9. 未決事項（要レビュー）

- ハング検知の対象範囲（全 running / 明示登録のみ）と `HANG_THRESHOLD` 初期値。
- クリア契機を `UserPromptSubmit` とペーン消滅のみとするか、フォーカス到達クリア・時間減衰クリアも要件に含めるか（現行実装には存在するが要件未確定）。
- 横断ビューの提供形態（専用コマンド / tmux popup / SketchyBar クリック）の優先順。
- pane option の命名統一（`@claude_status` → `@agent_status`）に伴う移行コスト。
- 自作 vs 既存採用（§10.3）: 横断ビュー部分を観測型の agent-mux で置き換えるか、現行 dotfiles スタックに統合した自作を貫くか（管理型の agtx / Agent of Empires は既存ワークフローを置換するため却下）。

## 10. 既存ツール調査 (Prior Art)

「処理が止まったエージェントの視覚通知 / 複数セッション監視」は需要が大きく、複数の既存ツールがある。現状 [opensessions](https://github.com/ataraxy-labs/opensessions) を採用中で、これを脱却しようとしている。車輪の再発明を避けるため調査結果を記録する。

### 10.1 主要ツール比較

| ツール | 形態 | 検知方式 | 状態 | tmux | マルチツール | ハング検知 |
|--------|------|---------|------|:--:|:--:|:--:|
| [opensessions](https://github.com/ataraxy-labs/opensessions)（現行） | tmux サイドバー (Rust) | JSONL transcript ポーリング + HTTP push API | done / error / interrupted | ◯ サイドバー pane | Amp/Claude/Codex/OpenCode | × |
| [Recon](https://agent-wars.com/news/2026-03-14-recon-tmux-tui-claude-code-sessions) | tmux-native TUI (Rust) | ペーン status-bar スキャン + `~/.claude/sessions/{PID}.json` + JSONL | working / input / idle / new | ◯ popup overlay + table | Claude のみ | × |
| [Claude Code Agent View](https://code.claude.com/docs/en/agent-view)（公式 `claude agents`） | CC 内蔵画面 | ネイティブ（background session） | Needs input / Working / Completed | △ CC 自身の画面のみ | Claude のみ | × |
| [tap-to-tmux](https://github.com/flavio87/tap-to-tmux) | hooks → 通知 | hooks | 完了/要対応（通知のみ） | △ | 複数 | × |
| [Claude-Code-Agent-Monitor](https://github.com/hoangsonww/Claude-Code-Agent-Monitor) | Web ダッシュボード | hooks | Kanban (session/tool/subagent) | × | Claude | × |
| [agent-sessions](https://github.com/jazzyalex/agent-sessions) | macOS アプリ | transcript 解析 | 履歴ブラウズ + limits | × | 多数 (Codex/Claude/Cursor/Pi/Gemini…) | × |

### 10.1b 選定軸: 観測型 vs 管理型（最重要）

「tmux 対応か」ではなく「既存の複数ペーン/ウィンドウ/セッションのワークフローを壊さずに横断観測できるか」で選別する。
本要件のワークフローは「ユーザーが自分の tmux レイアウト上で複数ペーンに Claude 等を自由に立ち上げ、それらを横断的に把握する」もの。自前のセッション/worktree を専有してエージェント起動を肩代わりする管理型は、このワークフローを置き換えてしまうため却下する。

| 型 | 定義 | ワークフロー | 判定 |
|----|------|------------|:--:|
| 観測型 | 既存の任意ペーンを受動的に発見・表示・ジャンプ。起動はユーザーが従来どおり | 非破壊 | 採用候補 |
| 管理型 / オーケストレーター | 自前 tmux セッション/server・worktree を専有し、エージェントを当該ツール経由で起動 | 置換 | 却下 |

| ツール | 型 | 対応エージェント | 既存ペーン観測 | 判定 |
|--------|----|----------------|:--:|:--:|
| [agent-mux](https://github.com/leonardcser/agent-mux) | 観測型 | Claude / OpenCode / Gemini / Codex | ◯ 既存ペーンを発見・プレビュー・ジャンプ。`~/.tmux.conf` に watcher 追加のみ | 採用候補（マルチツール×非破壊で最適合） |
| [Recon](https://agent-wars.com/news/2026-03-14-recon-tmux-tui-claude-code-sessions) | 観測型 | Claude のみ | ◯ CC 無改変・introspection | Claude 専用で不足 |
| [opensessions](https://github.com/ataraxy-labs/opensessions)（現行） | 観測型寄り | Amp/Claude/Codex/OpenCode | ◯ transcript 監視 + サイドバー pane / `_os_stash` | 現行・脱却検討中 |
| [Agent of Empires](https://github.com/njbrake/agent-of-empires) | 管理型 | Pi 等多数 | × `aoe add --cmd claude` で自前セッション専有・worktree/Docker | 却下（ワークフロー置換） |
| [agtx](https://github.com/fynnfluegge/agtx) | 管理型 | Claude/Codex/Gemini/OpenCode/Cursor/Copilot | × 専用 tmux server・task ごとに window/worktree・kanban orchestrator | 却下（ワークフロー置換） |

要点:
- 既存ワークフロー非破壊で横断観測できるのは観測型のみ。マルチツール×非破壊で最適合は agent-mux。Recon は同型だが Claude 専用。
- pi まで含む網羅性は Agent of Empires が高いが管理型のため却下。「対応の広さ」より「ワークフローを壊さないこと」を優先する。
- 観測型であっても「ハング/無応答検知」「既存 dotfiles の SketchyBar/Slack/リモート・コンテナ連携への統合」はいずれも未対応 → ここが自作の差別化点。横断ビュー UI を採用するなら agent-mux を参考/併用候補とする。

### 10.2 検知方式の選択肢（既存ツールから学んだ代替状態源）

ペーン文字列 grep（現行 `scan`、Recon の status-bar スキャン）以外に、より堅牢な状態源がある:

- hooks（settings.json）: イベント駆動。最も即時・確実だが idle は idle_prompt の制約あり（§4.1）。
- JSONL transcript tailing（`~/.claude/projects/**/*.jsonl`）: 最終メッセージ種別から running/stop を判定。opensessions が採用。hooks 補完に有効。
- PID 連携セッション JSON（`~/.claude/sessions/{PID}.json`）: tmux ペーン PID → CC セッションを確実に対応付け。Recon が採用。`workspace_map.json` ヒューリスティックより堅牢で、正本マッピングに使える可能性。

→ 本仕様の正本は pane option（hooks 駆動）を維持しつつ、マッピングと取りこぼし救済に PID 連携 JSON / JSONL tailing を補助採用する方針を検討する。

### 10.3 自作 vs 採用の判断 → 方針確定: 完全自作 (A)

確定方針: 既存スクリプト群の再編による完全自作。agent-mux は設計参考のみ（コードは取り込まない）。

判断理由:
- 差別化点（ハング検知・pane option 正本・SketchyBar/Slack 統合・リモート/コンテナ）はどのみち全て自作必須。
- 横断ビューは既存の `tmux-claude-badge.sh` / `tmux-claude-focus.sh` / `claude-status.sh` が既に全ペーン列挙・状態集約を行っており、薄い popup 追加で実現できる。
- 外部バイナリ依存を増やさず install.sh で Linux 再現可能（リポジトリのポータビリティ方針に合致）。状態モデル二重化も避ける。

不採用:
- B（agent-mux 無改変併用）: 横断ビュー TUI のためだけに外部バイナリ依存 + 状態二重化を抱えるのは割に合わない。
- C（agent-mux フォーク+パッチ）: フォーク維持コスト・upstream 乖離。「ワークアラウンド禁止・根本治療」方針に反する。

## 11. 実装ロードマップ

完全自作 (A) を前提とした実装順序。各フェーズ完了後に E2E（§8）で確認してから次へ。

1. 状態モデル基盤: pane option 正本化（`@agent_status` / `@agent_icon` / `@agent_heartbeat`）。`tmux-claude-pane.sh` を set/clear/集約の中核に再編、`scan` ヒューリスティック廃止。多ツール対応リネーム（`claude` → `agent`）。
2. hooks 統一配線: §4.1 対応表で全ツール（Claude/Codex/Cursor/Command Code/pi）を統一。欠落配線（ペーンアイコン set 全状態、`UserPromptSubmit` クリア、Command Code の Stop）を追加。idle は idle_prompt 依存を最小化し Stop 主体に。
3. ハング検知: heartbeat 更新（PreToolUse/PostToolUse/UserPromptSubmit）+ watcher（running かつ無更新 > 閾値、出力ハッシュ差分併用）。`HANG_THRESHOLD` 初期値を実測調整。
4. 通知面の派生ビュー化: `tmux-claude-badge.sh`（ウィンドウバッジ）・SketchyBar・Slack を pane option 集約から導出に統一。`ai-notify.sh` は派生ビュー出力に限定。
5. 横断集約ビュー: 全 session/window/pane（+リモート取り込み）を走査する一覧 + tmux popup + ジャンプ。agent-mux の観測・ジャンプ作法を参考。
6. リモート/コンテナ統合: ファイル store 取り込み（既存 watch 経路）を pane option へ反映。heartbeat も転送。
7. クリーンアップ: 旧経路・未使用コード削除、ドキュメント更新（agent-infrastructure.md の Completion Notify を本仕様へ集約）。

未決事項（§9）はフェーズ着手時に確定する。

### 11.1 実装状況

| フェーズ | 状態 | 主な成果物 |
|---------|------|-----------|
| 1 状態モデル基盤 | 完了 | `tmux-claude-pane.sh`(正本化/`@agent_*`/start/heartbeat/scan廃止)、`badge.sh`/`focus.sh` 追従 |
| 2 hooks 統一配線 | 完了 | `ai-notify.sh`(共通入口で pane 更新)、`claude-settings.json`(start/heartbeat 追加)、`commandcode-settings.json`(統一) |
| 3 ハング検知 | 完了 | `tmux-claude-pane.sh hang-scan`(出力ハッシュ併用)、`tmux-agent-hang-watch.sh`(単一インスタンス watcher)、`claude-hooks.tmux` 起動 |
| 4 ペーン表示 | 完了(a) / 保留(b) | (a) 6テーマ `pane-border-format` にアイコン+緊急度色。(b) SketchyBar 派生化は保留 |
| 5 横断集約ビュー | 完了 | `tmux-agent-status.sh`(list/popup)、`prefix + a` バインド |
| 6 リモート/コンテナ統合 | 完了 | 横断ビューが file store(`/tmp/claude/status`)を集約・ホスト識別・ウィンドウ単位ジャンプ・local 重複排除 |
| 7 クリーンアップ | 進行中 | 本仕様の進捗反映、`agent-infrastructure.md` ポインタ更新 |

注: 全て dotfiles 内の編集のみ。反映には settings 再生成（install.sh 相当）+ tmux 設定リロードが必要。

### 11.2 ツール別の配線状況・制約

全ツールが pane option (@agent_status) を立て、横断ビュー/サイドバー/ペーンアイコンに出る。
codex/cursor/pi は pane_current_command が全て `node` でコマンド識別不可のため、コマンド/title
ヒューリスティック検出は採らず、各ツールのネイティブ機構で push する方式に統一した。

| ツール | 配線 | start/running | heartbeat(hang検知) | 停止表示 |
|--------|------|:--:|:--:|------|
| Claude / Command Code | hooks(settings.json) | ◯ | ◯ | complete/idle/permission |
| pi | extension(`agent-notify.ts`) | ◯(session_start) | ◯(tool_call) | turn_end→idle |
| cursor | hooks(`cursor-hooks.json`) | ◯(beforeSubmitPrompt) | ◯(shell/edit) | stop→idle |
| codex | notify(単一・turn完了のみ) | × | × | turn完了→idle |

- codex の制約: notify は turn 完了時しか発火しない。実行中の running 表示・ハング検知は不可
  （idle のみ）。codex 側に他フックが無いための根本制約。
- 反映には各ツールの設定再生成(install.sh 相当)+ 当該エージェントの再起動が必要
  （hooks/extension はプロセス起動時に読まれるため）。
- リモートの `error` 欠落: リモート/コンテナ経路は `ai-notify` の SketchyBar 状態（idle/permission/complete/none）でファイルへ書くため `error` が `none` に丸められ横断ビューに出ない。修正は `ai-notify` リモート分岐の状態マッピング要改修。
- SketchyBar 派生化(4b)保留: 現行ファイルベース経路で動作。pane option 集約への一本化は未実施。
- クリア契機（§9）: フォーカス/時間減衰クリアの是非は未確定。現状は `complete` の10秒自動消去のみ既存挙動として維持。
