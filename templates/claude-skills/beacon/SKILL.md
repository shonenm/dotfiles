---
name: beacon
description: 現在の環境をaerospaceワークスペースに紐づけます。通知バッジを正しいワークスペースに表示するために使用します。
user-invocable: true
---

# Beacon - ワークスペース登録

現在の環境（tmuxウィンドウ/VSCode統合ターミナル）を指定されたaerospaceワークスペースに登録します。

## 使用方法

ユーザーが `/beacon <workspace番号>` と入力したら、以下のスクリプトを実行してください：

```bash
__HOME__/dotfiles/scripts/beacon.sh <workspace番号>
```

## 例

ユーザー入力: `/beacon 3`

実行するコマンド:
```bash
__HOME__/dotfiles/scripts/beacon.sh 3
```

## 注意事項

- 引数にはaerospaceのワークスペース番号を指定（1-9, A-Z等）
- 実行結果をユーザーに表示してください
