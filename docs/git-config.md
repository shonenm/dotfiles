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

# === Core ===
[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

# === Delta (diff viewer) ===
[delta]
    navigate = true
    dark = true

# === Init ===
[init]
    defaultBranch = main

# === Diff ===
[diff]
    algorithm = histogram
    colorMoved = plain
    mnemonicPrefix = true
    renames = true

# === Merge ===
[merge]
    conflictstyle = zdiff3

# === Push ===
[push]
    default = simple
    autoSetupRemote = true
    followTags = true

# === Fetch ===
[fetch]
    prune = true
    pruneTags = true

# === Pull ===
[pull]
    rebase = true

# === Rebase ===
[rebase]
    autoSquash = true
    autoStash = true
    updateRefs = true

# === Rerere (Reuse Recorded Resolution) ===
[rerere]
    enabled = true
    autoupdate = true

# === Branch/Tag display ===
[column]
    ui = auto

[branch]
    sort = -committerdate

[tag]
    sort = version:refname

# === UX ===
[help]
    autocorrect = 10

[commit]
    verbose = true
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

## 設定項目リファレンス

### Delta（diff viewer）

| 設定 | 値 | 説明 |
|------|-----|------|
| `core.pager` | delta | diffビューアーとしてdeltaを使用 |
| `interactive.diffFilter` | delta --color-only | インタラクティブステージング時の色付きdiff |
| `delta.navigate` | true | n/Nでdiffセクション間を移動 |
| `delta.dark` | true | ダークテーマ |

### Diff

| 設定 | 値 | 説明 |
|------|-----|------|
| `diff.algorithm` | histogram | より賢いdiffアルゴリズム（デフォルトのmyersより改善） |
| `diff.colorMoved` | plain | 移動されたコードブロックを色分け表示 |
| `diff.mnemonicPrefix` | true | a/b表記をi/w/c（index/worktree/commit）に |
| `diff.renames` | true | ファイル名変更を検出・表示 |

### Merge

| 設定 | 値 | 説明 |
|------|-----|------|
| `merge.conflictstyle` | zdiff3 | 競合時に元のコードも表示（3方向マージ） |

### Push/Fetch/Pull

| 設定 | 値 | 説明 |
|------|-----|------|
| `push.default` | simple | 現在のブランチを同名リモートブランチにpush |
| `push.autoSetupRemote` | true | 初回push時に自動でupstream設定 |
| `push.followTags` | true | ローカルタグを自動push |
| `fetch.prune` | true | リモートで削除されたブランチをローカルからも削除 |
| `fetch.pruneTags` | true | リモートで削除されたタグも削除 |
| `pull.rebase` | true | pull時にmergeではなくrebase |

### Rebase

| 設定 | 値 | 説明 |
|------|-----|------|
| `rebase.autoSquash` | true | `fixup!`コミットを自動squash |
| `rebase.autoStash` | true | rebase前に自動stash、後に自動unstash |
| `rebase.updateRefs` | true | スタックしたブランチをrebase時に更新 |

### Rerere（Reuse Recorded Resolution）

| 設定 | 値 | 説明 |
|------|-----|------|
| `rerere.enabled` | true | 競合解決を記録・再利用 |
| `rerere.autoupdate` | true | 記録した解決を自動適用 |

### Branch/Tag表示

| 設定 | 値 | 説明 |
|------|-----|------|
| `column.ui` | auto | ブランチ一覧をカラム表示 |
| `branch.sort` | -committerdate | ブランチを最新コミット順にソート |
| `tag.sort` | version:refname | タグをセマンティックバージョン順にソート |

### UX改善

| 設定 | 値 | 説明 |
|------|-----|------|
| `init.defaultBranch` | main | 新規リポジトリのデフォルトブランチ名 |
| `help.autocorrect` | 10 | コマンドのtypo時、1秒後に自動実行 |
| `commit.verbose` | true | コミットメッセージ編集時にdiff全体を表示 |

## 動作確認コマンド

### Rerere

```bash
# テスト用リポジトリで競合を作成・解決・リセット・再マージ
# 2回目のマージで自動解決されれば有効
ls .git/rr-cache/  # ディレクトリがあればOK
```

### Diff

```bash
git diff HEAD~1  # histogramアルゴリズムで表示
git diff --color-moved  # 移動コードの色分け確認
```

### Push

```bash
git checkout -b test-branch
git push  # -u なしでupstream設定される
```

### Rebase

```bash
# 未コミット変更がある状態でpull
echo "test" >> file.txt
git pull  # 自動stash/unstash
```

### Branch表示

```bash
git branch  # 最新コミット順・カラム表示
git tag     # セマンティックバージョン順
```

### Autocorrect

```bash
git stauts  # → 1秒後に git status が実行
```

## グローバルignore

`~/.config/git/ignore`（XDG準拠、Git自動認識）:

```
# macOS
.DS_Store

# Claude Code local settings
**/.claude/settings.local.json
```

**注意**: `core.excludesfile`の設定は不要。Gitは`~/.config/git/ignore`を自動で読み込む。

## 関連ドキュメント

- [1Password連携](./1password-integration.md) - 1Password CLIの詳細設定
