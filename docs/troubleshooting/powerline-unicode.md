# Powerline / Nerd Font 文字が Claude Code で破損する

**日付**: 2026-01-30
**環境**: Claude Code (Claude Opus 4.5), macOS, dotfiles 内の starship.toml / tmux テーマ

## 症状

Powerline 半月角丸文字（U+E0B6 ``, U+E0B4 ``）を含むファイルを Claude Code の Write / Edit ツールで編集すると、該当文字が別のバイト列に置換されてファイルが破損する。

対象ファイル例:
- `common/starship/.config/starship.toml` — 全セクションの format 行
- `common/tmux/.config/tmux/tokyonight.tmux` — ステータスバー定義
- `scripts/regenerate-tmux-theme.sh` — テーマ生成スクリプト

### 具体的な破損パターン

```
# 元のバイト列 (正常)
ee 82 b6  → U+E0B6 (left rounded)
ee 82 b4  → U+E0B4 (right rounded)

# Claude 経由で書き込むと別の文字に化ける
```

Read ツールで読み取った際は一見正常に見えるが、Write / Edit ツールで書き戻す際にバイト列が変わる。Claude の内部処理でこれらの Private Use Area (PUA) 文字が正しくラウンドトリップできない。

## 原因

Powerline Symbols（U+E0B0〜E0BF）は Unicode Private Use Area に近い領域に割り当てられた特殊文字。Claude のテキスト処理パイプラインで、これらの文字のエンコード/デコードが正確に保存されない。

同様の問題が起きうる文字:
- Powerline Symbols: U+E0A0〜E0AF, U+E0B0〜E0BF
- Nerd Font Icons: U+F0000〜F3FFF (Supplementary PUA)
- 一部の CJK 互換文字

## 対処法

### 方法 1: Claude に Powerline 行を触らせない (推奨)

Powerline 文字を含まない行のみを Edit ツールで変更する。

```
# OK: Powerline 文字を含まない行
$git_metrics\  →  ${custom.git_diff}\
[git_metrics]  →  [custom.git_diff]
disabled = false  →  command = "..."

# NG: Powerline 文字を含む行を Edit / Write で書くと破損
format = '[─](fg:current_line)[](fg:cyan)...'
```

変更が必要な場合は、ユーザーが手動で該当行を編集する。Claude に変更内容を指示してもらい、自分でエディタで書き換える。

### 方法 2: 行番号指定の sed

変更対象行を特定し、Powerline 文字を含まない部分のみを sed で置換する。

```bash
# 行番号指定で安全に置換（Powerline 文字に触れない）
sed -i '' '6s/\$git_metrics/${custom.git_diff}/' starship.toml

# 注意: パターンが複数行にマッチする sed は危険
# disabled = false のような汎用文字列は行番号指定必須
sed -i '' '67s/disabled = false/command = "..."/' starship.toml
```

**注意**: `sed` のパターンマッチ置換（行番号なし）は、意図しない行まで置換するリスクがある。`disabled = false` のような汎用文字列は必ず行番号を指定すること。

### 方法 3: スクリプトで生成

`regenerate-tmux-theme.sh` のように、テーマファイルをスクリプトから生成する設計にする。スクリプト内で `printf` を使い UTF-8 バイト列を直接埋め込む。

```bash
LEFT=$(printf '\xee\x82\xb6')    # U+E0B6
RIGHT=$(printf '\xee\x82\xb4')   # U+E0B4
```

この方式なら Claude がスクリプトを編集しても、printf のエスケープシーケンスは ASCII なので破損しない。

## 予防策

- Powerline / Nerd Font 文字を含むファイルを Claude に Write させない
- 該当ファイルを変更する際は Edit ツールで Powerline 行以外のみ操作
- テーマファイルは生成スクリプト経由で管理し、直接編集を避ける
- Claude に変更を依頼する場合、「format 行はユーザーが手動変更」と明示する
