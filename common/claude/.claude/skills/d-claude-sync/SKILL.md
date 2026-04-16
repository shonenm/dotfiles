---
name: d-claude-sync
description: dotfiles の Claude 設定（スキル・エージェント・ルール・フック）をプロジェクトに export、またはプロジェクトの設定を dotfiles に import します。
user-invocable: true
arguments: "<import|export> [<description>]"
argument-hint: "<import|export> [<skill-agent-rule-hook-or-feature-description>]"
when_to_use: "Use when the user wants to port dotfiles Claude configuration to a project, or promote project-specific Claude configuration into dotfiles."
---

# Claude Sync - dotfiles ↔ プロジェクト Claude 設定移植

dotfiles の `.claude/` 設定（スキル・エージェント・ルール・フック）をプロジェクトに export する、またはプロジェクトの `.claude/` 設定を dotfiles に import する。

## 引数

| 引数 | 説明 |
|------|------|
| `import` | プロジェクトの `.claude/` 設定 → dotfiles |
| `export` | dotfiles の `.claude/` 設定 → プロジェクト |
| `[description]` | 移植対象の名前・説明（省略時は網羅調査） |

### 使用例

```
/d-claude-sync import                          # プロジェクト全設定を調査して import 候補を提案
/d-claude-sync import "_review スキルを持ってきたい"
/d-claude-sync import "PR レビューの仕組みを dotfiles に取り込みたい"
/d-claude-sync import "stop hook の処理"

/d-claude-sync export                          # dotfiles 全設定を調査して export 候補を提案
/d-claude-sync export "_commit"
/d-claude-sync export "コミット・PR 関係をチームに配りたい"
/d-claude-sync export "ralph エージェント"
```

## 移植対象の種類

| 種類 | dotfiles パス | プロジェクト パス |
|------|--------------|-----------------|
| スキル | `~/.claude/skills/_<name>/SKILL.md` | `.claude/skills/<name>/SKILL.md` |
| エージェント | `~/.claude/agents/<name>/<name>.md` | `.claude/agents/<name>/<name>.md` |
| ルール | `~/.claude/rules/<name>.md` | `.claude/rules/<name>.md` または `CLAUDE.md` に統合 |
| フック | `~/.claude/hooks/<name>.sh` + settings.json | `.claude/hooks/<name>.sh` + `.claude/settings.json` |

## 手順

### 1. 引数の解析

第1引数から方向を取得（`import` または `export`）。  
それ以降の文字列を description として扱う。description は省略可。

### 2. 設定インベントリの収集

以下を並列で実行:

```bash
# dotfiles 側
ls ~/dotfiles/common/claude/.claude/skills/
ls ~/dotfiles/common/claude/.claude/agents/
ls ~/dotfiles/common/claude/.claude/rules/
ls ~/dotfiles/common/claude/.claude/hooks/

# プロジェクト側
ls .claude/skills/ 2>/dev/null || echo "(なし)"
ls .claude/agents/ 2>/dev/null || echo "(なし)"
ls .claude/rules/ 2>/dev/null || echo "(なし)"
ls .claude/hooks/ 2>/dev/null || echo "(なし)"
cat .claude/settings.json 2>/dev/null || echo "(なし)"
```

description が指定された場合は、関連しそうなファイルの内容を読む。  
description がない場合は、各 `SKILL.md` / `*.md` / `*.sh` の frontmatter + 冒頭数行を読んでインベントリを構築する。

### 3a. import モード（プロジェクト → dotfiles）

**description なし（網羅調査）**:

1. プロジェクトの `.claude/` 以下を全種類について調査
2. dotfiles に存在しないもの・より汎用化できそうなものを特定
3. 各候補を以下の観点で評価:
   - **汎用性**: 他のプロジェクトでも使えるか
   - **個人効率**: 自分の作業フローに価値を加えるか
   - **差別性**: dotfiles 既存設定と重複しないか

**description あり（絞り込み）**:

1. description からターゲットを特定:
   - 設定名が明示されている → 対応ファイルを直接読む
   - 機能・仕組みの説明 → 関連しそうなファイルを探して読む
2. 対象の内容を読み込み、dotfiles 化の方針を具体的に提示

**提案内容（種類別）**:

- **スキル**: 汎用化すべき箇所（プロジェクト固有パス・ツール名・設定名など）、新スキル名（`_` プレフィックス付き）、配置先 `~/dotfiles/common/claude/.claude/skills/_<name>/SKILL.md`
- **エージェント**: 役割・制約の汎用化方針、dotfiles 既存エージェントとの整合性
- **ルール**: そのまま流用か一部抽象化が必要かの判断、既存 `rules/` ファイルへのマージ可否
- **フック**: スクリプトの汎用化方針（プロジェクト固有パスの除去など）、dotfiles `settings.json` への hooks 追記内容

### 3b. export モード（dotfiles → プロジェクト）

**description なし（網羅調査）**:

1. dotfiles の `.claude/` 以下の全設定を調査
2. プロジェクトの既存 `.claude/` 設定と照合
3. 各候補を以下の観点で評価:
   - **プロジェクト適合性**: このプロジェクトのスタック・ワークフローに関連するか
   - **チーム配布価値**: チームメンバーが使えるか、個人専用のままが良いか
   - **カスタマイズ必要度**: そのまま使えるか、変更が必要か

**description あり（絞り込み）**:

1. description からターゲットを特定（dotfiles 側から）
2. 対象の内容を読み込み、プロジェクト向けのカスタマイズ方針を具体的に提示

**提案内容（種類別）**:

- **スキル**: このプロジェクトのスタック・規約への特化方針、チーム向けの言語調整、配置先 `.claude/skills/<name>/SKILL.md`
- **エージェント**: プロジェクト固有コンテキストの追加方針、`allowed-tools` の調整
- **ルール**: プロジェクト `CLAUDE.md` への統合か `.claude/rules/` への配置かの判断
- **フック**: スクリプトのプロジェクト固有化方針、個人パス（`~/dotfiles/` 等）をプロジェクト内相対パスに変換する方法、`.claude/settings.json` への追記内容

### 4. 提案フォーマット

```
## [import|export] 候補

### スキル
| 名前 | 概要 | カスタマイズ量 | 優先度 |
|------|------|----------------|--------|
| `name` | ... | 小/中/大 | 高/中/低 |

### エージェント / ルール / フック
...（存在する場合のみ表示）

---
実施するものを名前または番号で指定してください。"all" で全候補を実施します。
```

ユーザーが選択を返答したら、選択された対象に対して移植処理（ファイル生成）を実行する。

## 注意事項

- 提案のみ行い、ユーザーが選択するまでファイルの作成・変更は行わない
- dotfiles 側のパスは `~/dotfiles/common/claude/.claude/` を基準にする
- プロジェクト側のパスは現在の作業ディレクトリ (cwd) の `.claude/` を基準にする
- export 時は dotfiles の元ファイルを変更しない（プロジェクト側にコピーして変更する）
- フックの export 時、個人の環境に依存したパス・設定（`~/dotfiles/` 等）はプロジェクト内の相対パスに変換する
- チーム配布を意図した export は、個人的な設定・APIキー・パスへの依存を除去する
