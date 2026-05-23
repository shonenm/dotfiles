# pi-coding-agent (OpenCode Go + Codex)

[pi](https://pi.dev/) はミニマルな terminal coding harness。MCP / sub-agents / permission popup / plan mode を持たず、CLI extensions と skills で組み立てる思想。dotfiles では OpenCode Go と Codex のサブスクリプションで動かす前提で構築している。

参考: [OpenCode Go + pi-coding-agent のすゝめ](https://zenn.dev/kimuson/articles/pi-coding-agent-with-opencode-go)

## 構成

| 要素 | 役割 | 配置 |
| --- | --- | --- |
| pi CLI | エージェント本体 | `config/packages.npm.txt` の `@earendil-works/pi-coding-agent` (npm global) |
| AGENTS.md | グローバル指示書 | `common/pi/.pi/agent/AGENTS.md` → `~/.pi/agent/AGENTS.md` |
| pueue | バックグラウンドタスク・並列 delegation 用キュー | `config/Brewfile` (mac), `packages.linux.{apt,alpine}.txt` (linux) |

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
```

認証情報は `~/.pi/credentials.json` に保存される (gitignore 済み、stow 対象外)。

サブスクリプションのおすすめ組合せ:

- **OpenCode Go ($10/月)** をメイン
  - `deepseek-v4-pro`, `kimi-k2.6`, `glm-5.1` 等の Open Model にアクセス
- **Codex ($20 or $100/月)** をフォールバックの Frontier モデル枠
  - `gpt-5.5`, `gpt-5.4`, `gpt-5.3-codex-spark` 等
- Claude Pro/Max は pi 経由だと利用規約上 extra usage 課金になるため非推奨

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
