# Git設定管理

dotfilesでのGit設定の管理・共有の仕組み。

## 概要

Git設定を2つのファイルに分離して管理:

| ファイル | 管理 | 内容 |
|----------|------|------|
| `~/.gitconfig` | dotfiles (共有) | delta, merge設定など共通設定 |
| `~/.gitconfig.local` | ローカル専用 | user.name, user.email など |

## アーキテクチャ

```
dotfiles/common/git/.gitconfig
        ↓ stow (シンボリックリンク)
~/.gitconfig
        ↓ [include] ディレクティブ
~/.gitconfig.local (マシン固有、dotfiles管理外)
```

### なぜ分離するか

- **問題**: `git config --global`は`~/.gitconfig`に書き込む
- **問題**: `~/.gitconfig`はdotfilesでシンボリックリンクされている
- **結果**: `git pull`でdotfilesを更新すると、user設定が上書きされる

**解決策**: `[include]`で別ファイルを読み込み、マシン固有設定を分離

## セットアップ

### 1. dotfilesインストール

```bash
./install.sh
```

実行されること:
- `~/.gitconfig` → `dotfiles/common/git/.gitconfig` のシンボリックリンク作成
- `~/.gitconfig.local` の空ファイル作成（存在しない場合）

### 2. Git user設定

1Passwordから取得して設定:

```bash
setup_git_from_op
```

出力:
```
Git config updated: shonenm <your@email.com>
```

### 1Passwordの設定

以下のアイテムを作成:

| 項目 | 値 |
|------|-----|
| Vault | `Personal` |
| アイテム名 | `Git Config` |
| フィールド `name` | あなたの名前 |
| フィールド `email` | あなたのメールアドレス |

**注意**: `username`ではなく`name`を使用（usernameは1Passwordの予約フィールド）

確認:
```bash
op read "op://Personal/Git Config/name"
op read "op://Personal/Git Config/email"
```

## ファイル構成

### ~/.gitconfig (dotfiles管理)

```gitconfig
# Git configuration
# User settings are stored in ~/.gitconfig.local (not tracked by dotfiles)

[include]
    path = ~/.gitconfig.local

[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true
    dark = true

[merge]
    conflictstyle = zdiff3
```

### ~/.gitconfig.local (ローカル専用)

```gitconfig
[user]
    name = shonenm
    email = your@email.com
```

## 動作フロー

### 新規マシンセットアップ

```
1. ./install.sh 実行
   └─ ~/.gitconfig がシンボリックリンクされる
   └─ ~/.gitconfig.local が空で作成される

2. setup_git_from_op 実行
   └─ 1Passwordからname/email取得
   └─ ~/.gitconfig.local に書き込み

3. 完了
   └─ git config user.name → 設定済み
   └─ git config user.email → 設定済み
```

### dotfiles更新時

```
1. git pull (dotfilesリポジトリ)
   └─ ~/.gitconfig (共通設定) が更新される
   └─ ~/.gitconfig.local は影響なし ✓

2. user設定は保持される
```

### 別マシンとの共有

```
マシンA                          マシンB
~/.gitconfig.local               ~/.gitconfig.local
[user]                           [user]
    name = shonenm                   name = shonenm
    email = personal@example.com     email = work@example.com
        ↑ 個人用                         ↑ 仕事用

~/.gitconfig (共通)              ~/.gitconfig (共通)
[include]                        [include]
    path = ~/.gitconfig.local        path = ~/.gitconfig.local
[core]                           [core]
    pager = delta                    pager = delta
    ...                              ...
```

同じdotfilesを使いながら、マシンごとに異なるuser設定が可能。

## コマンドリファレンス

### 設定確認

```bash
# 現在のuser設定
git config user.name
git config user.email

# 設定ファイルの場所を確認
git config --list --show-origin | grep user

# .gitconfig.localの内容
cat ~/.gitconfig.local
```

### 手動設定

1Passwordを使わない場合:

```bash
# 直接編集
cat > ~/.gitconfig.local << EOF
[user]
    name = Your Name
    email = your@email.com
EOF
```

または:

```bash
# git configで設定（.gitconfigに書き込まれる）
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

**注意**: `git config --global`は`~/.gitconfig`に書き込むため、dotfiles更新で上書きされる可能性あり。`~/.gitconfig.local`への直接書き込みを推奨。

### 設定のリセット

```bash
# .gitconfig.localを削除して再設定
rm ~/.gitconfig.local
setup_git_from_op
```

## トラブルシューティング

### user.name/emailが設定されていない

```bash
# 確認
git config user.name  # 出力なし = 未設定

# 解決
setup_git_from_op
```

### setup_git_from_opでエラー

```bash
# "Failed to read name" の場合
# → 1Passwordのフィールド名が正しいか確認
op item get "Git Config" --vault Personal

# 1Passwordにサインインしていない
eval $(op signin)
```

### dotfiles更新後にuser設定が消えた

古い構成（[include]なし）の可能性:

```bash
# .gitconfigを確認
head -10 ~/.gitconfig

# [include]がなければdotfilesを更新
cd ~/dotfiles && git pull
```

## 関連ドキュメント

- [1Password連携](./1password-integration.md) - 1Password CLIの詳細設定
