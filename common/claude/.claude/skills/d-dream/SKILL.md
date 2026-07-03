---
name: d-dream
description: auto-memory の重複・矛盾・陳腐化を整理する（memory consolidation）
user-invocable: true
arguments: "[project-path]"
argument-hint: "[path to project dir, defaults to cwd]"
when_to_use: "Use when the user says 'dream', '記憶の整理', 'memory consolidation', or 'clean up memory'."
---

# Memory Dream — auto-memory consolidation

Claude Code の auto-memory (`~/.claude/projects/{dir}/memory/`) を整理し、重複・矛盾・陳腐化エントリを除去する。

## 対象

`~/.claude/projects/{project_dir_canonical}/memory/` 配下:
- `MEMORY.md` — 索引（常時ロード、200 行以内）
- `*.md` — 個別メモリファイル（frontmatter 付き）

`project_dir_canonical` は引数があればそのパス、なければ cwd から解決する。

## 手順

### 1. Scan（現状把握）

```bash
MEMORY_DIR="$HOME/.claude/projects/$(echo "$PROJECT_PATH" | tr '/' '-')/memory"
ls -la "$MEMORY_DIR"
```

全メモリファイルを読み、以下を記録する:
- ファイル数、各ファイルの type・name・description
- MEMORY.md の行数

### 2. Diagnose（問題検出）

各メモリファイルについて以下をチェック:

- **陳腐化**: 存在しないファイル・関数・フラグへの参照。`ls` / `grep` で現存確認
- **重複**: 複数ファイルが同じ知見を異なる言い回しで記述
- **矛盾**: 同じ事柄について異なる結論を述べている
- **相対日付**: "昨日"、"先週" など → 絶対日付に変換不能なら削除
- **CLAUDE.md/rules との重複**: ハーネスのルールファイルに既に書かれている内容の再掲
- **索引の不整合**: MEMORY.md にあるがファイルが無い、またはその逆

### 3. Fix（修正）

検出した問題ごとに修正:

- 陳腐化 → 現存確認して更新、確認できなければ削除
- 重複 → 1 ファイルにマージし他方を削除
- 矛盾 → 最新の値で解決（曖昧ならユーザー確認）
- 索引不整合 → MEMORY.md を実ファイルと同期

成果ファイルの原則:
- **経緯・履歴を残さない**: Why の技術的因果は残してよいが、セッション ID・失敗回数・学習日は除去
- **メタ注記を残さない**: 「X と重複するのでここには書かない」のような注記は不要、黙って消す
- 現行で正しい知見・ルールだけ残す

### 4. Report（報告）

変更の要約をユーザーに報告する:
- 削除したファイルとその理由
- マージしたファイル
- 更新した内容
- MEMORY.md の行数 before/after

変更はユーザーのレビュー後にコミットする（自動コミット・push しない）。

## 注意

- dream 出力は hallucination 混入の懸念があるため、参照先の現存確認を必ず行う
- 判断に迷う矛盾はユーザーに確認する
- originSessionId は消さない（frontmatter の一部として保持）
