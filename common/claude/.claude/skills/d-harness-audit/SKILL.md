---
name: d-harness-audit
description: Claude Code ハーネス構成を監査し、改善提案・スキャフォルディングを行う
user-invocable: true
arguments: "[scope] [focus]"
argument-hint: "[project|dotfiles|scaffold] [hooks|skills|agents|rules|permissions|all]"
when_to_use: "Use when the user wants to audit, improve, or scaffold Claude Code harness configuration (settings, hooks, skills, agents, rules)."
---

# Harness Audit - Claude Code ハーネス監査・改善

ハーネスエンジニアリングの観点からClaude Code の設定を監査し、改善提案とスキャフォルディングを行う。

## 引数

| 引数 | 説明 |
|------|------|
| `scope` | 監査対象: `project` (デフォルト), `dotfiles`, `scaffold` |
| `focus` | 焦点: `hooks`, `skills`, `agents`, `rules`, `permissions`, `all` (デフォルト) |

### 使用例

```
/d-harness-audit                           # 現在のプロジェクトを全項目監査
/d-harness-audit project hooks             # プロジェクトのフックのみ監査
/d-harness-audit dotfiles                  # dotfiles のハーネスを全項目監査
/d-harness-audit dotfiles skills           # dotfiles のスキルのみ監査
/d-harness-audit scaffold                  # 新プロジェクト用ハーネスをスキャフォルド
```

## 手順

### 1. 引数の解析

- 第1引数: scope (`project`, `dotfiles`, `scaffold`)。省略時は `project`
- 第2引数: focus (`hooks`, `skills`, `agents`, `rules`, `permissions`, `all`)。省略時は `all`

### 2. インベントリ収集

scope に応じて以下を並列実行:

#### project scope

```bash
# ハーネス構成ファイル
cat .claude/settings.json 2>/dev/null || echo "(なし)"
cat .claude/settings.local.json 2>/dev/null || echo "(なし)"
cat .claude/config.json 2>/dev/null || echo "(なし)"
ls .claude/skills/ 2>/dev/null || echo "(なし)"
ls .claude/agents/ 2>/dev/null || echo "(なし)"
ls .claude/rules/ 2>/dev/null || echo "(なし)"
ls .claude/hooks/ 2>/dev/null || echo "(なし)"
ls .claude/commands/ 2>/dev/null || echo "(なし)"
ls .claude/templates/ 2>/dev/null || echo "(なし)"
head -5 CLAUDE.md 2>/dev/null || echo "(なし)"
```

#### dotfiles scope

```bash
ls ~/dotfiles/common/claude/.claude/skills/
ls ~/dotfiles/common/claude/.claude/agents/
ls ~/dotfiles/common/claude/.claude/rules/
ls ~/dotfiles/common/claude/.claude/hooks/
cat ~/.claude/settings.json 2>/dev/null || echo "(なし)"
```

### 3. 監査チェックリスト

focus が `all` の場合は全項目実行。特定 focus の場合は該当セクションのみ。

#### 3a. settings.json 監査

- [ ] `permissions.deny` に `Read(.env*)` と `Bash(sudo:*)` が含まれるか
- [ ] project メタデータ (name, description, stack) が記述されているか
- [ ] development.testCommands が定義されているか (CI/CD 連携)

#### 3b. hooks 監査

- [ ] PostToolUse フック: Write/Edit 後の品質フィードバック (tsc/lint/test) があるか
- [ ] Stop フック: 自律ループ制御が必要なスキルに対応しているか
- [ ] PreCompact フック: 長時間ループの状態保存があるか
- [ ] 参照先スクリプトが全て存在するか (壊れたフック検出)
- [ ] フック内で適切なタイムアウトが設定されているか

#### 3c. skills 監査

- [ ] SKILL.md に必要なフロントマター (name, description, user-invocable) があるか
- [ ] allowed-tools が適切に制限されているか (最小権限)
- [ ] プロジェクト固有スキルとグローバルスキルの重複がないか
- [ ] 使われていないスキルがないか

#### 3d. agents 監査

- [ ] エージェント定義に name, description, tools フロントマターがあるか
- [ ] tools リストが役割に対して適切か (過剰/不足)
- [ ] model 指定がコスト効率的か (重い処理に haiku を使っていないか等)
- [ ] 複数エージェント間で責務が明確に分離されているか

#### 3e. rules 監査

- [ ] 1 ルール = 1 関心事の原則を守っているか
- [ ] CLAUDE.md とルールファイルの間で矛盾・重複がないか
- [ ] ルールが簡潔か (詳細手順がルールに書かれていないか → スキルに分離すべき)

#### 3f. permissions 監査

- [ ] settings.json の deny に機密ファイルアクセスが含まれるか
- [ ] settings.local.json の allow リストに不要な広範囲パターンがないか
- [ ] `Bash(rm:*)` 等の破壊的操作が allow に含まれていないか

### 4. 結果レポート

```
## Harness Audit Report — [scope]

### サマリー
| カテゴリ | 状態 | 項目数 |
|---------|------|--------|
| settings | OK / 要改善 / 未設定 | N |
| hooks | ... | N |
| skills | ... | N |
| agents | ... | N |
| rules | ... | N |
| permissions | ... | N |

### 検出事項

#### [Critical] ...
説明と改善案

#### [Warning] ...
説明と改善案

#### [Info] ...
説明と改善案

### 改善アクション
1. ...
2. ...

---
実施するアクションを番号で指定してください。"all" で全アクションを実施します。
```

### 5. scaffold モード

新プロジェクト用のハーネス一式をスキャフォルドする。

#### 生成物

```
.claude/
├── settings.json          # プロジェクトメタデータ・権限テンプレート
├── rules/                 # (空、プロジェクト固有ルール用)
├── agents/                # (空、プロジェクト固有エージェント用)
└── commands/              # (空、プロジェクト固有コマンド用)
```

#### settings.json テンプレート

```json
{
  "project": {
    "name": "<project-name>",
    "description": "<one-line description>",
    "type": "<web-application|library|cli|service>",
    "stack": {}
  },
  "development": {
    "testCommands": [],
    "qualityGates": {
      "typescript": true,
      "linting": true,
      "testing": true
    }
  },
  "permissions": {
    "deny": ["Bash(sudo:*)", "Read(.env*)"]
  }
}
```

ユーザーにプロジェクト情報をヒアリングし、テンプレートを埋めて生成する。

## 注意事項

- 監査結果は提案のみ。ユーザーが選択するまでファイルの作成・変更は行わない
- scaffold モードでも既存ファイルを上書きしない。衝突がある場合はマージ提案を行う
- settings.local.json は個人設定のため、scaffold 対象外とする
- dotfiles scope の監査結果で「プロジェクト側に export すべき」と判断した項目は `/d-claude-sync export` への誘導を行う
