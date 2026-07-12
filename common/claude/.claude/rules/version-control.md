# Version Control

Git を version-control write の標準とする。`.jj/` が存在するリポジトリでも jj は使わず git 経路で作業する。

- 作業前に `git status` で状態を確認する
- 変更確認は `git status` / `git diff` / `git log` を使う
- ブランチ作成は `git checkout -b <name>`
- コミットは変更したファイルを明示的に `git add <path>` してから `git commit -m "<message>"`。`git add .` / `-A` は使わない
- push はユーザーが明示的に要求した時のみ `git push`
- develop / main への commit / push はしない。作業は feature ブランチで行い PR を出す
- プロジェクト側に jj 用ルール (例: `version-control-jj.md`) が存在しても従わない。上記 git 経路を優先する
