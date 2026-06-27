# dotfiles

macOS/Linux両環境で動作する開発環境設定。GNU Stowでシンボリックリンクを管理。

## ディレクトリ構造

- `common/` - 共通設定（Mac/Linux両方で使用）
- `mac/` - macOS専用設定
- `linux/` - Linux専用設定
- `scripts/` - インストール・セットアップスクリプト
- `docs/` - ドキュメント

## 主要ツール設定

| ツール | パス |
|--------|------|
| Neovim | `common/nvim/.config/nvim/` |
| Zsh | `common/zsh/.zshrc.common`, `mac/zsh/.zshrc`, `linux/zsh/.zshrc` |
| Tmux | `common/tmux/.config/tmux/` |
| Starship | `common/starship/.config/starship.toml` |

## 開発ルール

### ポータビリティ（必須）

- 変更は`install.sh`でリモートLinux環境に再現可能であること
- macOS専用機能を追加する場合はLinux版も同時に実装
- 新しいツールは`scripts/mac.sh`と`scripts/linux.sh`の両方に追加

### 問題解決

- 対症療法ではなく根本治療を優先
- ワークアラウンド追加前に根本原因を調査・修正
- ハードコードを避け設定可能な形で実装

### Version Control

`.jj/` が存在するリポジトリでは Jujutsu (`jj`) を version-control write の標準にする。

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

### ベストプラクティス

- 変更前にWeb検索で最新のベストプラクティスを調査
- より良いツールやアプローチがあれば提案
- 非推奨の機能や古いパターンを使用しない

### パフォーマンス

- シェル起動時間に影響する変更は最適化を考慮
- 遅延ロード（lazy loading）を活用
- 不要なサブシェル起動を避ける

### scripts/ 命名規約

`~/dotfiles/scripts` は PATH に含まれており、スクリプトはコマンドとして直接実行可能。

- ユーザー向けコマンド: 拡張子なし（例: `wt`, `ralph-crew`, `beacon`）
- ライブラリ: `-lib.sh` 拡張子付き（例: `wt-lib.sh`, `ralph-lib.sh`）
- 内部スクリプト（tmux, hooks, launchd）: `.sh` 拡張子付き

### ドキュメント

- 変更に関連する`docs/`内のmdファイルを更新
- 新機能には必要に応じてドキュメントを追加
- README.mdとの整合性を保つ

## Stowの使い方

新しい設定を追加する場合:

```bash
# 1. ディレクトリ構造を作成（実際のパスを再現）
mkdir -p common/<tool>/.config/<tool>

# 2. 設定ファイルを配置
# 例: common/tool/.config/tool/config.toml

# 3. Stowでシンボリックリンクを作成
cd ~/dotfiles
stow -d common -t ~ <tool>

# 4. 確認
ls -la ~/.config/<tool>
```

OS固有の設定は`mac/<tool>/`または`linux/<tool>/`に配置。

### ランタイムファイルの扱い

ツールがランタイムファイル（認証情報、キャッシュ、履歴等）を生成する場合:

1. `.stow-local-ignore` を使用してランタイムファイルを stow の対象から除外
   - 例: `common/claude/.stow-local-ignore`
2. `.gitignore` でランタイムファイルを無視
   - パッケージ内に `.gitignore` を配置（例: `common/claude/.claude/.gitignore`）
3. `install.sh` は `--no-folding` オプションを使用し、ディレクトリ全体がシンリンクされることを防止

これにより、設定ファイルのみがシンリンクされ、ランタイムファイルは `~/.config/tool/` に直接作成されます。

## Git Merge/Rebase コンフリクト解決

merge/rebase のコンフリクト解決は `/d-conflict-resolve` スキルを使用すること。
