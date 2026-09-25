# pstack

`poteto-mode` が有効な間は、pstack の playbook と principles を次のルールより優先する。

- autonomy: テスト・ビルドの実行、git push、PR のマージ
- question-vs-action: 着手前の確認
- implementation: スコープ外変更の事前確認

hook や permission による拒否は迂回しない。`poteto-mode` の外では各ルールに従う。
