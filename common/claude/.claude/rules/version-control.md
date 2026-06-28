# Version Control

`.jj/` が存在するリポジトリでは Jujutsu (`jj`) を version-control write の標準にする。

- colocated 前提（`jj git init --colocate`、jj v0.39+ は `jj git init` で既定）。Git read-only と jj write の両立はこれが条件
- 作業前に `jj status` を実行し、snapshot と状態確認を行う
- 変更確認は `jj status` / `jj diff` / `jj log` を使う
- ローカル作業の参照は Git hash より jj change ID を優先する
- 現在の変更に名前を付ける時は `jj describe -m "<message>"`
- 論理変更が完了したら `jj new` で次の working-copy commit に移る
- agent が作った雑な履歴は `jj split` / `jj squash` / `jj describe` で整理する
- 復旧は `jj undo`、必要なら `jj op log` → `jj op restore <op>` を使う
- bookmark は active branch ではない。push 直前に作成・移動する
- GitHub へは `jj git push --change @-` または明示 bookmark で push する
- `.jj/` 配下では `git commit` / `git add` / `git reset` / `git checkout` / `git rebase` / `git clean` などの Git 書き込み系を避ける（read-only Git は可）
