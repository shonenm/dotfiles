# Agent共有設定レイヤー

標準形式で共有できるskillと、横断原則を `~/.config/agent/` に置く。MCP設定はruntime間で要件が異なるため、Claude Codeとは分離する。

## 構成

```text
~/.config/agent/
├── skills/<name>/SKILL.md   Agent Skills Standard
├── knowledge/*.md           人が参照する横断原則
└── mcp.json                 pi / Command Code用MCP設定
```

リポジトリ上の正本は `common/agent/.config/agent/`。GNU Stowで同じパスへリンクする。

## 読み込み先

| 対象 | 読み込み方法 |
|---|---|
| pi | `settings.json` の `skills` に `~/.config/agent/skills` を指定 |
| Command Code | shared skill pathを探索し、MCPはinstall時に `cmd mcp add-json` で登録 |
| Claude Code | Claude固有skillは `~/.claude/skills`。MCPはClaude専用設定から登録 |
| Cursor / Codex | 対応する標準skillだけ利用し、runtime固有設定は共有しない |

## 責任分離

### Skills

共有skillの正本は `common/agent/.config/agent/skills/<name>/SKILL.md`。pi固有skillとの重複コピーは置かない。Ponytailはpi package / Claude pluginを正本とする。

### MCP

- pi / Command Code: `common/agent/.config/agent/mcp.json`
- Claude Code: `common/claude/.config/claude/mcp.json`

server集合とpermission機構が異なるため、「全runtimeで1ファイル」とはしない。詳細は[MCPレイヤー](mcp-layer.md)を参照。

### Knowledge

`knowledge/` はcommunication、security、web researchの横断原則を記録する参照資料であり、自動注入されない。runtimeの挙動を変える場合は、piの `APPEND_SYSTEM.md` やClaudeのrulesなど実際の読み込み先を更新する。

## 新しい共有skill

1. `common/agent/.config/agent/skills/<name>/SKILL.md` を作る
2. frontmatterに `name` と `description` を記載する
3. runtime固有tool名を使う場合は、そのruntimeに限定するか利用可能性を明記する
4. pi再起動または `/reload` 後に発見されることを確認する

プロジェクト全体の開発原則は[`CLAUDE.md`](../../../CLAUDE.md)、pi固有の運用は[pi概要](overview.md)を参照。
