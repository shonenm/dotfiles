# pstack

> **由来:** **Plugin** [pstack](https://github.com/cursor/plugins/tree/main/pstack)（Cursor / Claude Code）/ [oh-my-pstack](https://github.com/shrimpwtf/oh-my-pstack)（Pi）/ **Configuration** `rules/pstack.*`・Pi `AGENTS.md`・`scripts/install-common.sh`（[区分](../provenance.md#区分)）

poteto（Lauren Tan）の skill 集。入口の `poteto-mode` がタスクを playbook（bug fix、feature、refactoring、shipping など）に振り分け、`how` / `why` / `architect` / `arena` / `swarm` / `interrogate` / `tdd` などを呼ぶ。Claude Code は同じ repo の生成ツリー `harness/pstack/claude-code` を使い、Pi は非公式の移植版を使う。

## 導入

| ツール | 導入元 | 導入方法 | 呼び出し |
| --- | --- | --- | --- |
| Cursor | `cursor/plugins`（公式） | 手動で `/add-plugin pstack` | `/poteto-mode` |
| Claude Code | `cursor/plugins`（公式） | `install_pstack`（`scripts/install-common.sh`） | `/pstack:poteto-mode` |
| Pi | `shrimpwtf/oh-my-pstack` | `settings.json` の `packages` | `/skill:poteto-mode` |

Cursor の marketplace plugin は CLI・設定ファイルから導入できないため `install.sh` の対象外とする。Cursor IDE か CLI の `/plugin` で導入し、`/setup-pstack` でモデル割当を決める。

Claude Code 版は Cursor の用語を同梱の `docs/harness/claude-code.md` で読み替える。hook は持たない。第三者 marketplace は自動更新されないため、`install_pstack` は導入済みなら `claude plugin update` を実行する。旧非公式版 `pstack@pstack-claude` が残っていれば削除する。

`/pstack:setup-pstack` はモデル割当を `~/.claude/rules/pstack-models.md` に書く。dotfiles では管理せず、既定値のまま使う。

## ルールの優先順位

`poteto-mode` が有効な間だけ pstack を既存ルールより優先する。hook・permission・Pi extension による拒否は対象外。

| ツール | 正本 | 優先対象 |
| --- | --- | --- |
| Cursor | `common/cursor/.cursor/rules/pstack.mdc` | autonomy / question-vs-action / implementation |
| Claude Code | `common/claude/.claude/rules/pstack.md` | 同上 |
| Pi | `common/pi/.pi/agent/AGENTS.md` の `pstack` 節 | `APPEND_SYSTEM.md` と `AGENTS.md` の委譲・review・完了基準の制限 |

## 確認

```bash
claude plugin list | grep pstack@cursor-plugins
pi list | grep oh-my-pstack
```
