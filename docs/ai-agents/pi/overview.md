# pi-coding-agent (OpenCode Go + Codex + Cursor)

[pi](https://pi.dev/) はミニマルな terminal coding harness。MCP / sub-agents / permission popup / plan mode を持たず、CLI extensions と skills で組み立てる思想。dotfiles では OpenCode Go / Codex を主軸に、Cursor サブスク向けに [pi-cursor-agent](https://www.npmjs.com/package/pi-cursor-agent) プロバイダも同梱している。

参考: [OpenCode Go + pi-coding-agent のすゝめ](https://zenn.dev/kimuson/articles/pi-coding-agent-with-opencode-go)

## 構成

| 要素 | 役割 | 配置 |
| --- | --- | --- |
| pi CLI | エージェント本体 | `config/packages.npm.txt` の `@earendil-works/pi-coding-agent` (npm global) |
| pi-cursor-agent | Cursor サブスク → pi プロバイダ | `settings.json` の `packages` → `pi install npm:pi-cursor-agent` |
| pi-dynamic-workflows | Claude Code-style workflow / fan-out orchestration | `settings.json` の `packages` → `pi install npm:@quintinshaw/pi-dynamic-workflows` |
| pi-loop | dynamic goal loop、cron/event re-wake loop、background monitor | `settings.json` の `packages` → `pi install npm:@trevonistrevon/pi-loop` |
| pi-goal | `/goal` で完了まで継続する goal mode | `settings.json` の `packages` → `pi install npm:@narumitw/pi-goal` |
| AGENTS.md | グローバル指示書 | `common/pi/.pi/agent/AGENTS.md` → `~/.pi/agent/AGENTS.md` |
| pueue | バックグラウンドタスク・並列 delegation 用キュー | `config/Brewfile` (mac), `packages.linux.{apt,alpine}.txt` (linux) |

## LoopとGoalの使い分け

完了条件を持つ有限の実装作業には `/loop <goal>` のdynamic loop、または `/goal <goal>` を使う。dynamic loopは各iterationの完了後に`LoopUpdate`で次回wakeを設定するため、agent実行中のtimer tickでは`maxFires`を消費しない。

`LoopCreate`によるcron loopはCI監視など、時間間隔そのものに意味がある観測・polling専用とする。cron loopの`maxFires`は実作業の完了回数ではなくschedule発火回数を数え、agent実行中に通知がcoalesceされても増加する。

## セットアップ

### 1. install.sh で pi 本体を入れる

```bash
cd ~/dotfiles
./install.sh
```

`install_npm_packages` が `@earendil-works/pi-coding-agent` を含めて global install する。`stow` で `common/pi/` がリンクされ `~/.pi/agent/AGENTS.md` が配置される。

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
# OpenCode Go を選択 → ブラウザで OAuth
> /login
# ChatGPT (Codex) を選択 → ブラウザで OAuth
> /login
# Cursor Agent を選択 → ブラウザで OAuth (pi-cursor-agent)
```

認証情報は `~/.pi/credentials.json` に保存される (gitignore 済み、stow 対象外)。

サブスクリプションのおすすめ組合せ:

- **OpenCode Go ($10/月)** をメイン
  - `deepseek-v4-pro`, `kimi-k2.6`, `glm-5.1` 等の Open Model にアクセス
- **Codex ($20 or $100/月)** をフォールバックの Frontier モデル枠
  - `gpt-5.5`, `gpt-5.4`, `gpt-5.3-codex-spark` 等
- **Cursor Pro/Team** — pi ハーネス内で Composer / Claude / GPT 等を使う場合
  - `/model cursor-agent/composer-2-fast` 等 (`enabledModels`: `cursor-agent/*`)
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

### 3. pueue デーモンを起動

並列 delegation や長時間プロセスを pi 経由で扱う場合 pueue デーモンが必要。

```bash
pueued -d        # daemonize
pueue status
```

systemd / launchd 自動起動を組む場合は別途設定 (TODO)。

## 使い方

### 対話モード

```bash
pi
```

`AGENTS.md` の指示に従い、必要に応じてサブエージェント (別 pi インスタンス) を spawn する設計。

### 非対話モード (`-p`)

```bash
pi --model 'opencode-go/deepseek-v4-pro:high' \
   --fallback-models 'openai-codex/gpt-5.4:low' \
   -p '<instructions>'
```

### 並列 delegation (pueue)

```bash
pueue add -i --print-task-id -- "pi --model 'opencode-go/deepseek-v4-pro:high' -p '<instruction>' < /dev/null"
pueue wait <task-id>
pueue log <task-id>
```

## Web Research

詳細は [web-research.md](web-research.md) を参照。

dotfiles の拡張により Web Research Layer が利用可能。SearXNG + Jina + ローカルキャッシュで API key 不要の調査基盤。

## カスタマイズ

### モデル選択を変更する

`common/pi/.pi/agent/AGENTS.md` の "Model selection" セクションを編集。プロバイダ / モデル名 / effort を変えれば次回起動から反映される (シンボリックリンクなので即時反映)。

### TUI テーマ

`tokyonight-high-contrast` を標準テーマとして `common/pi/.pi/agent/themes/` で管理する。通常は `settings.json` の `theme` がこれを選ぶ。Pi を再起動すると反映され、調整中のテーマファイルは Pi 上で自動再読込される。

### 表示を簡潔にする

標準設定では思考ブロックを隠し、起動ヘッダーを省略し、`/tree` はツール結果を除外して開く。必要な詳細だけをキーバインドで表示する。

- `Ctrl+T`: 思考ブロックを展開/折り畳み
- `Ctrl+O`: ツール出力を展開/折り畳み
- `Esc` を2回: `/tree` を開く。tree 内の `Ctrl+T` でツール結果を表示/非表示
- `/statusline compact`: フッターを1行表示に切り替え
- 入力中の既知 skill 名はアクセント色でハイライトされる（`/reload` または再起動で skill 一覧を再読込）。

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
