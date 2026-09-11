# pi-coding-agent (Codex + Cursor)

> **由来:** **Upstream** pi本体・provider / **Plugin** settings.json導入package / **Configuration** settings・AGENTS.md・テーマ / **Custom** extensions / **Local patch** `scripts/patch-pi-tui.sh`（[区分](../../provenance.md#区分)）

[pi](https://pi.dev/) はミニマルな terminal coding harness。MCP / sub-agents / permission popup / plan mode を持たず、CLI extensions と skills で組み立てる思想。dotfiles では Codex を主軸に、Cursor サブスク向けに [pi-cursor-agent](https://www.npmjs.com/package/pi-cursor-agent) プロバイダも同梱し、xAI の Grok も選べるようにしている。`enabledModels` は `openai-codex/*`、`cursor-agent/*`、`opencode-go/*`、`xai/*`。

## 構成

| 要素 | 役割 | 配置 |
| --- | --- | --- |
| pi CLI | エージェント本体 | `config/packages.npm.txt` の `@earendil-works/pi-coding-agent` (npm global) |
| pi-tui narrow terminal patch | tmux focus zoomで1列/1行になった間は描画を停止し、Piの終了とscrollを防止 | `scripts/patch-pi-tui.sh` (Local patch) |
| pi-cursor-agent | Cursor サブスク → pi プロバイダ | `settings.json` の `packages` → `pi install npm:pi-cursor-agent` |
| pi-dynamic-workflows | Claude Code-style workflow / fan-out orchestration | `settings.json` の `packages` → `pi install npm:@quintinshaw/pi-dynamic-workflows` |
| pi-loop | dynamic goal loop、cron/event re-wake loop、background monitor | `settings.json` の `packages` → `pi install npm:@trevonistrevon/pi-loop` |
| pi-goal | `/goal` で上限付き自動継続を行う goal mode | `settings.json` の `packages` + `pi-goal.json` |
| pi-hermes-memory | scope付きlong-term memory、session検索、background review、consolidation | `settings.json` の `packages` + `hermes-memory-config.json` |
| UI比較package | header / footer / editor / theme / browser workspaceを実機比較 | `settings.json` の `packages`（下記参照） |
| AGENTS.md | グローバル指示書 | `common/pi/.pi/agent/AGENTS.md` → `~/.pi/agent/AGENTS.md` |
| pueue | バックグラウンドタスク・並列 delegation 用キュー | `config/Brewfile` (mac), `packages.linux.{apt,alpine}.txt` (linux) |

## 対話・Plan・Goalの使い分け

通常対話では、質問・課題感・暫定要件を実装依頼として扱わない。`実装して`などの明示後に変更を開始し、動作するfirst implementationと最小の関連検証まで進めて利用者へ制御を返す。実装中の通常のedit/bashはYOLO modeで止めず、方針変更や節目を自然言語で報告する。

要件や方式を先に固める場合は`/plan`を使う。read-onlyで調査・計画し、画面上のExecute選択または明示的な実装指示まで変更しない。

「全件完了まで継続」のように無人完遂を明示する場合だけ`/goal <goal>`を使う。`pi-goal.json`で自動応答を4回、無進捗を2回に制限し、上限到達時は状態を保持して停止する。必要なら利用者が`/goal resume`を選ぶ。利用者が「loop」と表現しても、時間間隔に意味がなければcron loopへ変換しない。

`/loop <goal>`のdynamic loopは、iteration上限内の反復作業に使う。各iterationの完了後に`LoopUpdate`で次回wakeを設定するため、agent実行中のtimer tickでは`maxFires`を消費しないが、iteration上限に達すると終了する。

`LoopCreate`によるcron loopはCI監視など、時間間隔そのものに意味がある観測・polling専用とする。cron loopの`maxFires`は実作業の完了回数ではなくschedule発火回数を数え、agent実行中に通知がcoalesceされても増加する。

## セットアップ

### 1. install.sh で pi 本体を入れる

```bash
cd ~/dotfiles
./install.sh
```

`install_npm_packages` が `@earendil-works/pi-coding-agent` を含めて global installし、続けて`patch-pi-tui.sh`を適用する。pi-tui 0.84.1はterminal幅1で幅3の行を描画すると例外終了するため、極小paneの間だけ描画を停止するlocal patchを再適用可能な形で管理する。`stow` で `common/pi/` がリンクされ `~/.pi/agent/AGENTS.md` が配置される。

確認:

```bash
pi --version
ls -la ~/.pi/agent/AGENTS.md  # dotfiles へのシンボリックリンクであること
```

### 2. サブスクリプション認証

`pi` を起動し `/login` で認証する。

```bash
pi
> /login
# ChatGPT (Codex) を選択 → ブラウザで OAuth
> /login
# Cursor Agent を選択 → ブラウザで OAuth (pi-cursor-agent)
> /login
# xAI を選択 → ブラウザで OAuth (Grok)
```

認証情報は `~/.pi/credentials.json` に保存される (gitignore 済み、stow 対象外)。

サブスクリプションのおすすめ組合せ:

- **Codex ($20 or $100/月)** をメイン
  - `gpt-5.6-sol`, `gpt-5.6-luna`, `gpt-5.3-codex-spark` 等
- **Cursor Pro/Team** — pi ハーネス内で Composer / Claude / GPT 等を使う場合
  - `/model cursor-agent/composer-2-fast` 等 (`enabledModels`: `cursor-agent/*`)
- **xAI / Grok** — `xai/grok-4.6` 等 (`enabledModels`: `xai/*`)
- **opencode go** — Kimi / GLM / MiniMax / Qwen / DeepSeek 等のオープンモデル (`enabledModels`: `opencode-go/*`)。利用するモデルは現在の `/model` 一覧から選ぶ。
- Claude Pro/Max は pi 経由だと利用規約上 extra usage 課金になるため非推奨

### Cursor Provider (pi-cursor-agent)

[pi-cursor-agent](https://github.com/sudosubin/pi-frontier/tree/main/pi-cursor-agent) は Cursor API 経由で推論し、ツール実行は pi 側にブリッジする。dotfiles 拡張 (permission-gate, mcp-gateway, statusline) がそのまま効く。

| 項目 | 内容 |
| --- | --- |
| パッケージ | `npm:pi-cursor-agent` (`settings.json` → `packages`) |
| 前提 | `cursor-agent` CLI (`install.sh`) |
| 認証 | pi 内 `/login` → Cursor Agent |
| モデル例 | `cursor-agent/composer-2-fast`, `cursor-agent/claude-opus-4-6` |

`@netandreus/pi-cursor-provider` は Cursor CLI 子プロセス方式で、ツールが CLI 側で実行されるため pi ハーネス統合には不向き。dotfiles では採用していない。

**注意:** コミュニティ製・非公式 API。Cursor の仕様変更で動かなくなる可能性あり。

### 3. pueueを確認

`agent-delegation.ts` はpi起動時にpueue daemonの起動を試みる。通常は手動の常駐設定を追加しない。

```bash
pueue status
# daemonが停止している場合だけ:
pueued -d
```

## 使い方

### 対話モード

```bash
pi
```

subagent / workflowは利用者がdelegation、並列調査、multi-agent reviewを明示した場合だけ使う。通常実装の品質向上を理由に自動reviewせず、reviewは原則1 passとする。明示されたpueue backgroundだけcustom `delegate_agent`を使う。PiのWeb検索が利用不能な場合は、Web調査依頼に限り共有`deep-research` skillからCodex native searchへephemeral委譲する。

### 非対話モード (`-p`)

```bash
pi --model 'openai-codex/gpt-5.6-sol:high' \
   --fallback-models 'openai-codex/gpt-5.6-luna:medium' \
   -p '<instructions>'
```

### 並列 delegation (pueue)

```bash
pueue add -i --print-task-id -- "pi --model 'openai-codex/gpt-5.6-luna:medium' -p '<instruction>' < /dev/null"
pueue wait <task-id>
pueue log <task-id>
```

## tmux状態連携

`agent-notify.ts`は`agent_start`から`agent_settled`までを1つのrunning区間として扱い、stream/tool進捗を5秒間隔のheartbeatへ変換する。更新は直列化され、`turn_end`途中でidleへ戻る競合を起こさない。詳細は[AI agent状態管理](../../specs/agent-stop-notification.md)を参照。

## Web Research

詳細は [web-research.md](web-research.md) を参照。

dotfiles の拡張により Web Research Layer が利用可能。通常はSearXNG + Jina + ローカルキャッシュを使い、検索backendが利用不能な場合だけ`codex --search exec --ephemeral`のnative searchへfallbackする。Codexには`medium` reasoning、primary-source URL、根拠quoteを要求し、親sessionで取得元を検証する。

## カスタマイズ

### モデル選択を変更する

`subagent` の既定モデルは `common/pi/.pi/agent/settings.json` の `subagents.defaultModel` / `defaultThinking` / `modelScope.allow`、`workflow` は `common/pi/.pi/workflows/model-tiers.json` の全tierで管理する。両方の既定モデルは `openai-codex/gpt-5.6-luna` で、通常の呼び出しでは `model` を指定しない。変更する場合は現在のregistryに存在する `provider/model` を設定し、piを再起動する。許可リストへの追加だけではモデルは登録されず、registryへの登録も現在の認証での利用を保証しない。モデル指定なしの子起動で応答まで検証する。

pueue用の `delegate_agent` だけは独立しているため、必要なら `common/pi/.pi/agent/extensions/agent-delegation.ts` の `MODEL_TIERS` を編集する。runtimeの利用方針は `AGENTS.md` に記載する。

### TUI テーマ

`tokyonight-high-contrast` を標準テーマとして `common/pi/.pi/agent/themes/` で管理する。通常は `settings.json` の `theme` がこれを選ぶ。pi を再起動すると反映され、調整中のテーマファイルは pi 上で自動再読込される。

### 統合Pi UI shell

`extensions/statusline.ts`がheader、composer、footer、working indicator、terminal tab titleを単一ownerとして管理する。packageを重ねて同じsurfaceを後勝ちで上書きせず、既存のprompt history editorとskill highlightをwrapして入力機能を保持する。

- compact header: model、作業directory、Pi version
- state composer: `ASK` / `RUN` / `TOOL`、thinking level、context、`/status`導線
- footer: 作業directory、branch、model、context使用率、実行状態と操作案内、stash等の状態。幅が狭い場合も項目を省かず折り返す。contextの`CTX`ラベルは付けず、footerはゲージと割合、composerは割合のみ表示
- `/status`: project、model / thinking、context、background agents、表示対象のextension statusを確認するoverlay
- terminal tab: `READY` / `RUN` / tool名 / dirty状態
- working indicator: Tokyo Nightのaccentに合わせたPi orbit

`/statusline on|off`でfooterを表示・非表示にする。引数なしはtoggle。旧profile名（`detailed`、`balanced`、`minimal`、`compact`、`legacy`）と保存済み設定は`on`として扱い、幅によるprofile切り替えや行数上限は設けない。

Cursor上限、YOLO / Ponytail（FULL）、package数 / auto-update、TOK / COST / WEB / MCPはfooterにも`/status`にも表示しない。Cursor上限の問い合わせとtoken / cost / research統計の読み取りもstatuslineから削除している。permission、Ponytail、package管理、Web / MCPの機能自体は変更しない。

比較用packageはinstall状態を維持するが、surface ownershipが競合する`pi-open-tui`、`pi-beautiful-tui`、`pi-system-theme`のextension entrypointはfilterする。theme collection、Pi Studio、extmgr、tool pills、session／todo機能など、統合shellと重複しない機能は引き続き読み込む。

| Package | 状態・利用箇所 |
| --- | --- |
| `pi-open-tui` | install維持、UI entrypointは統合shellとの競合を避けてfilter |
| `awesome-pi-themes` | theme比較用に有効 |
| `pi-studio` | browser workspace、preview、annotationを有効 |
| `pi-extmgr` | package管理overlayを有効 |
| `pi-beautiful-tui` | install維持、UI entrypointはfilter |
| `pi-agent-extensions` | footer、workflow、周期的にworking messageを書き換えるwhimsicalをfilter。session / todo / prompt history等は有効 |
| `pi-system-theme` | Tokyo Night固定と競合するためentrypointをfilter |
| `git:github.com/tomsej/pi-ext` | custom footer、重複permission、pi-cloak、built-in `ctrl+x`と競合するleader-keyをfilter。tool pills等は有効 |

### 表示を簡潔にする

独自UI導入前の標準設定では思考ブロックを隠し、起動ヘッダーを省略し、`/tree` はツール結果を除外して開く。必要な詳細だけをキーバインドで表示する。

- `Ctrl+T`: 思考ブロックを展開/折り畳み
- `Ctrl+O`: ツール出力を展開/折り畳み
- `Ctrl+S`: 入力中の下書きを退避。入力欄が空の状態で再度押すと復元し、割り込み対応が終わってagentが停止した際も空欄なら自動復元する
- `Ctrl+R`: 現在の会話ブランチのプロンプト履歴を検索。文字入力で絞り込み、`↑↓`で選択、`Enter`で入力欄へ復元（自動送信しない）。`Esc`で下書きを変えずに戻る。改行は復元時に保持し、同じ入力は最新の1件にまとめる
- `Esc` を2回: `/tree` を開く。tree 内の `Ctrl+T` でツール結果を表示/非表示
- 実行中は現在のtoolと`Esc/Enter`をフッターに表示（`Esc`は停止、`Enter`はsteer）
- `/statusline off`: footerを非表示（`on`で再表示）
- `/status`: project、model / thinking、context、background agents、表示対象のextension statusをoverlayで一覧表示
- 入力中の既知 skill 名はアクセント色でハイライトされる（`/reload` または再起動で skill 一覧を再読込）。

`Ctrl+S` / `Ctrl+R`はcustom extensionの`prompt-stash.ts` / `prompt-history.ts`が担当する。built-in shortcutとの競合警告を避けるため、選択画面内のモデル選択保存・セッション並べ替えは`Alt+S`、セッション名変更は`Alt+R`へ`keybindings.json`で変更している。変更は`/reload`で反映される。

### Permission gate

`permission-system.json`の`yoloMode`と`settings.json`の`hideThinkingBlock`は有効のままにする。対話の承認境界はwrite permissionではなく、明示的な実装指示と`/plan`で管理するため、実装開始後の通常操作は止めない。

`common/pi/.pi/agent/extensions/permission-gate.ts`はdangerous shell commandを実行前に確認する。agentはセッション開始時のmain repositoryまたは既存worktreeで実装し、利用者の明示なしに別worktreeへ移動しない。worktree capacity追加は確認対象ではなくhard denyし、`git worktree add`と`pnpm wt provision`は実行しない。利用者が明示した既存pooled slotのclaim/listは許可する。capacity追加が必要な場合は利用者がpi外のterminalから実行する。

### 拡張機能

pi packages 経由で extensions / skills を追加:

```bash
pi install npm:@foo/pi-tools
pi list
```

dotfiles 管理にしたい場合は `common/pi/.pi/agent/AGENTS.md` に `/skill:<name>` の利用方針を追記し、パッケージ自体は `pi install` でローカル管理する (`~/.pi/packages/` は stow 対象外)。

## 関連

- [web-research.md](web-research.md) — Web Research Layer 詳細
- `config/packages.npm.txt` - pi 本体の npm パッケージ
- `common/pi/.pi/agent/AGENTS.md` - グローバル指示書
- `common/pi/.stow-local-ignore` - ランタイムファイル除外
