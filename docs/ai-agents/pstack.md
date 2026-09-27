# pstack

> **由来:** **Plugin** [pstack](https://github.com/cursor/plugins/tree/main/pstack)（Cursor）/ [pstack-claude](https://github.com/michael-denyer/pstack-claude)（Claude Code）/ [oh-my-pstack](https://github.com/shrimpwtf/oh-my-pstack)（Pi）/ **Configuration** `rules/pstack.*`・`pstack-models.md`・Pi `AGENTS.md`・`scripts/install-common.sh`（[区分](../provenance.md#区分)）

poteto（Lauren Tan）の skill 集。入口の `poteto-mode` がタスクを playbook（bug fix、feature、refactoring、shipping など）に振り分け、`how` / `why` / `architect` / `arena` / `swarm` / `interrogate` / `tdd` などを呼ぶ。Claude Code と Pi は非公式の移植版を使う。

## 導入

| ツール | 導入元 | 導入方法 | 呼び出し |
| --- | --- | --- | --- |
| Cursor | `cursor/plugins`（公式） | 手動で `/add-plugin pstack` | `/poteto-mode` |
| Claude Code | `michael-denyer/pstack-claude` | `install_pstack`（`scripts/install-common.sh`） | `/pstack:poteto-mode` |
| Pi | `shrimpwtf/oh-my-pstack` | `settings.json` の `packages` | `/skill:poteto-mode` |

Cursor の marketplace plugin は CLI・設定ファイルから導入できないため `install.sh` の対象外とする。Cursor IDE か CLI の `/plugin` で導入し、`/setup-pstack` でモデル割当を決める。

Claude Code 版の SessionStart hook は全セッションで `poteto-mode` へ誘導するため、`common/claude/.claude/pstack-models.md` の `session hook: off` で無効化している。モデル割当を変える場合は `/pstack:setup-pstack` がこのファイルを書き換える。

## ルールの優先順位

`poteto-mode` が有効な間だけ pstack を既存ルールより優先する。hook・permission・Pi extension による拒否は対象外。

| ツール | 正本 | 優先対象 |
| --- | --- | --- |
| Cursor | `common/cursor/.cursor/rules/pstack.mdc` | autonomy / question-vs-action / implementation |
| Claude Code | `common/claude/.claude/rules/pstack.md` | 同上 |
| Pi | `common/pi/.pi/agent/AGENTS.md` の `pstack` 節 | `APPEND_SYSTEM.md` と `AGENTS.md` の委譲・review・完了基準の制限 |

## 確認

```bash
claude plugin list | grep pstack@pstack-claude
pi list | grep oh-my-pstack
```
