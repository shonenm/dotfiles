---
name: d-grill-me
description: 実装前に plan / design を1問ずつ容赦なく詰問し、決定木の各分岐を解消して共通理解に到達する。既存ドキュメント・コードと照合し、用語整合 (docs/CONTEXT.md) と不可逆判断 (docs/adr/) をインライン記録する。
user-invocable: true
disable-model-invocation: true
arguments: "<plan-or-design-description>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, WebFetch, WebSearch
---

# Grill Me - 詰問による plan/design 詰め

実装前に、ユーザーの plan / design / feature 方向性を1問ずつ詰問し、決定木の各分岐を解消して共通理解に到達する。
意図・制約・隠れた前提・未検討の代替案を炙り出すフェーズ用。バグ探索ではない。

このスキルは grill-with-docs (Matt Pocock) をベースにする。プロジェクトに canonical なアーキテクチャドキュメント・型定義/契約モジュールがあれば、それを正解の基準として参照する。

## 詰問の進め方

- 1問ずつ質問する。各質問に対するフィードバックを待ってから次の質問へ進む。一度に複数問を出さない。
- 各質問には AI の推奨回答を理由とともに併記する。
- 決定木を分岐ごとに下る。決定間の依存を1つずつ解消する。
- コードベースやドキュメントを調べれば答えられる質問は、ユーザーに聞かず自分で調査する。
- 質問は AskUserQuestion ツールではなく通常のテキストで行い、ユーザーのターン返信を待つ (自由記述の議論を妨げないため)。

## セッション中の挙動

詰問しながら以下を常に行う:

- 既存モデルとの照合: プロジェクトのアーキテクチャドキュメント・型定義/契約モジュール・docs/CONTEXT.md の既存定義と矛盾する前提・用語使用を即座に指摘する。
- 曖昧な言葉を鋭くする: 多義的・曖昧な用語に canonical term を提案する (例: "account は Customer か User か")。
- 具体シナリオで境界を詰める: エッジケースのシナリオを提示し、境界・例外の扱いを確定する。
- コードとの相互参照: ユーザーの主張とコードが矛盾したら表面化する (例: "コードは Order 全体を cancel するが、partial cancellation を可能と言った。どちらが正しいか")。

## 永続化

決定が固まった時点で、バッチせず即座に書き戻す。

### 用語集 docs/CONTEXT.md

用語が解決するたびに docs/CONTEXT.md を更新する (遅延作成: ファイルが無ければ最初の用語解決時に作成)。
docs/CONTEXT.md は glossary 専用。実装詳細・spec・scratch pad にしない。

書式:

```markdown
# Context

## Language

### {用語}
1-2文の定義。関係・cardinality を示す。
_Avoid_: {非推奨のエイリアス}
```

ルール:
- opinionated に正規語を1つ選ぶ。矛盾は明示する。
- 定義は短く保つ。汎用プログラミング概念は含めない。
- 自然なクラスタで subheading 分割する。

### ADR docs/adr/

不可逆な設計判断は docs/adr/NNNN-slug.md として連番で記録する (遅延作成: ディレクトリが無ければ最初の ADR 必要時に作成)。

ADR を提案するのは以下3条件がすべて真のときのみ:
1. 元に戻すのが難しい (hard to reverse)
2. 文脈なしでは驚く判断 (surprising without context)
3. 実際のトレードオフの結果である (real trade-off)

書式 (最小):

```markdown
# {短いタイトル}

{文脈・決定・理由を1-3文}
```

任意で Status / Considered Options / Consequences を追記してよい。

qualify する判断種別: アーキテクチャ形状、統合パターン、lock-in を伴う技術選択、境界/スコープ、意図的な規約逸脱、コードに現れない制約、非自明な却下案。

## 終了

決定木が解消したら、カバーした内容のサマリを提示する:

- Decisions: 確定した設計判断
- Constraints: 確定した制約
- Open questions: 残った未解決事項 (あれば)
- 用語整合 / ADR: docs/CONTEXT.md・docs/adr/ への記録内容

サマリ提示後、スキルを終了する。実装は行わない。
