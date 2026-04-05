---
name: news-local
description: プロファイルに基づいてパーソナライズされたニュースを取得・提示します
user-invocable: true
disable-model-invocation: true
allowed-tools: WebSearch, WebFetch, Read
arguments: "[period]"
---

# News - パーソナライズドニュースダイジェスト

ユーザープロファイルに基づいて、指定期間のニュースを網羅的に検索し、カテゴリ別に整理して提示する。

## 引数

| 引数 | デフォルト | 説明 |
|------|-----------|------|
| `period` | `week` | 検索期間。`day`, `week`, `month` のいずれか |

### 使用例

```
/news           # 直近1週間のニュース
/news day       # 直近1日のニュース
/news month     # 直近1ヶ月のニュース
```

## 手順

### 1. プロファイルの読み込み

Read ツールで `~/.claude/news-profile.yaml` を読み込む。

ファイルが存在しない場合は以下のメッセージを出力して終了する:

```
プロファイルが見つかりません。

~/.claude/news-profile.yaml を作成してください。テンプレート:

personal:
  name: "氏名"
  company: "所属企業"
  role: "役割 (例: Backend Engineer)"
  location: "拠点 (例: Tokyo, Japan)"

interests:
  technical:
    - "技術的興味1 (例: Rust language)"
    - "技術的興味2 (例: Neovim ecosystem)"
  industry:
    - "業界の興味1 (例: developer tools)"
    - "業界の興味2 (例: cloud infrastructure)"
  companies:
    - "追跡企業1 (例: Anthropic)"
    - "追跡企業2 (例: Apple)"

テンプレートからコピーして作成:
cp ~/.claude/news-profile.example.yaml ~/.claude/news-profile.yaml
```

### 2. 期間パラメータの決定

`$ARGUMENTS` をパースし、期間を決定する:

| 入力 | 検索修飾子 | 表示ラベル |
|------|-----------|-----------|
| `day` | `past 24 hours` | `past day` |
| `week` (デフォルト) | `past week` | `past week` |
| `month` | `past month` | `past month` |

不正な値が指定された場合は `week` にフォールバックする。

### 3. 検索クエリの生成

プロファイルの各 interests カテゴリから検索クエリを生成する。以下のルールに従う:

- `interests.technical` の項目から 2-3 クエリ（ロール文脈を付加。例: "Rust backend production" ではなく "Rust language news"）
- `interests.industry` の項目から 1-2 クエリ
- `interests.companies` の項目から 1-2 クエリ（企業名 + "news" or "announcement"）
- 合計 5-8 クエリに収める
- 各クエリに期間修飾子を含める（例: "Rust language news past week"）
- 1つ「セレンディピティ枠」を設ける: プロファイルの周辺領域で、ユーザーが知らない可能性のあるトピックを検索する

### 4. 検索の実行

生成したクエリを WebSearch で実行する。

- 各クエリの結果からタイトルとURLを収集する
- 重複するURLは除去する
- プロファイルとの関連性が低い結果は除外する

### 5. 記事の選別と要約取得

検索結果から関連性の高い上位 8-12 記事を選別する。選別基準:

- プロファイルの興味との直接的な関連度
- 記事の新しさ（指定期間内のものを優先）
- ソースの多様性（同一ソースに偏らない）

選別した記事のうち、特に重要な 5-8 記事について WebFetch で詳細を取得する。
WebFetch が失敗した場合（ドメイン拒否等）は、WebSearch で得られた情報のみで要約を構成する。

### 6. 出力

以下のフォーマットでカテゴリ別に整理して出力する:

```markdown
# News Digest ({date}, {period_label})

## Technical

### [記事タイトル](URL)
Source: example.com
要約（2-3文）

### [記事タイトル](URL)
Source: example.com
要約（2-3文）

## Industry

### [記事タイトル](URL)
Source: example.com
要約（2-3文）

## Companies

### [記事タイトル](URL)
Source: example.com
要約（2-3文）

## Serendipity

### [記事タイトル](URL)
Source: example.com
要約（2-3文）
```

出力ルール:
- 各カテゴリに最低1記事、該当なしの場合はカテゴリごと省略
- 要約は日本語で2-3文
- 各記事にソースドメインを明記
- Serendipity カテゴリにはプロファイル周辺領域の記事を配置

## 注意事項

- WebSearch は 5-10 回、WebFetch は 5-8 回の範囲内で実行する
- 検索結果が少ない場合は無理に記事数を増やさない
- ペイウォール付きサイトの記事は WebSearch の情報のみで要約する
- 出力は日本語で行う
