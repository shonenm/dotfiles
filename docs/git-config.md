# Git Configuration Management

How Git configuration is managed and shared in dotfiles.

## Overview

Git configuration is split into two files:

| File | Management | Contents |
|------|------------|----------|
| `~/.gitconfig` | dotfiles (shared) | delta, merge settings, and other common settings |
| `~/.gitconfig.local` | Local only | user.name, user.email, etc. |

## Architecture

```
dotfiles/common/git/.gitconfig
        ↓ stow (symbolic link)
~/.gitconfig
        ↓ [include] directive
~/.gitconfig.local (machine-specific, not managed by dotfiles)
```

### Why Separate?

- **Problem**: `git config --global` writes to `~/.gitconfig`
- **Problem**: `~/.gitconfig` is symlinked by dotfiles
- **Result**: Running `git pull` on dotfiles overwrites user settings

**Solution**: Use `[include]` to load a separate file, isolating machine-specific settings

## Setup

### 1. Install dotfiles

```bash
./install.sh
```

What happens:
- Creates symbolic link `~/.gitconfig` → `dotfiles/common/git/.gitconfig`
- Creates empty `~/.gitconfig.local` (if it doesn't exist)

### 2. Git User Configuration

Retrieve from 1Password and configure:

```bash
setup_git_from_op
```

Output:
```
Git config updated: shonenm <your@email.com>
```

### 1Password Setup

Create the following item:

| Field | Value |
|-------|-------|
| Vault | `Personal` |
| Item Name | `Git Config` |
| Field `name` | Your name |
| Field `email` | Your email address |

**Note**: Use `name` instead of `username` (username is a reserved 1Password field)

Verify:
```bash
op read "op://Personal/Git Config/name"
op read "op://Personal/Git Config/email"
```

## File Structure

### ~/.gitconfig (managed by dotfiles)

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

# === Aliases ===
[alias]
    secrets = !gitleaks detect --verbose
    absorb = !git-absorb --and-rebase

# === ghq (Repository Management) ===
[ghq]
    root = ~/ghq
```

### ~/.gitconfig.local (local only)

```gitconfig
[user]
    name = shonenm
    email = your@email.com
```

## Workflow

### New Machine Setup

```
1. Run ./install.sh
   └─ ~/.gitconfig is symlinked
   └─ ~/.gitconfig.local is created empty

2. Run setup_git_from_op
   └─ Retrieve name/email from 1Password
   └─ Write to ~/.gitconfig.local

3. Complete
   └─ git config user.name → configured
   └─ git config user.email → configured
```

### When Updating dotfiles

```
1. git pull (dotfiles repository)
   └─ ~/.gitconfig (common settings) is updated
   └─ ~/.gitconfig.local is not affected ✓

2. User settings are preserved
```

### Sharing Between Machines

```
Machine A                        Machine B
~/.gitconfig.local               ~/.gitconfig.local
[user]                           [user]
    name = shonenm                   name = shonenm
    email = personal@example.com     email = work@example.com
        ↑ Personal                       ↑ Work

~/.gitconfig (common)            ~/.gitconfig (common)
[include]                        [include]
    path = ~/.gitconfig.local        path = ~/.gitconfig.local
[core]                           [core]
    pager = delta                    pager = delta
    ...                              ...
```

Use the same dotfiles while having different user settings per machine.

## Command Reference

### Check Configuration

```bash
# Current user settings
git config user.name
git config user.email

# Check configuration file locations
git config --list --show-origin | grep user

# View .gitconfig.local contents
cat ~/.gitconfig.local
```

### Manual Configuration

If not using 1Password:

```bash
# Direct edit
cat > ~/.gitconfig.local << EOF
[user]
    name = Your Name
    email = your@email.com
EOF
```

Or:

```bash
# Configure with git config (writes to .gitconfig)
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

**Note**: `git config --global` writes to `~/.gitconfig`, which may be overwritten by dotfiles updates. Direct writing to `~/.gitconfig.local` is recommended.

### Reset Configuration

```bash
# Delete .gitconfig.local and reconfigure
rm ~/.gitconfig.local
setup_git_from_op
```

## Troubleshooting

### user.name/email Not Set

```bash
# Check
git config user.name  # No output = not set

# Fix
setup_git_from_op
```

### Error with setup_git_from_op

```bash
# If "Failed to read name"
# → Verify field name is correct in 1Password
op item get "Git Config" --vault Personal

# Not signed in to 1Password
eval $(op signin)
```

### User Settings Disappeared After dotfiles Update

Possibly using old configuration (without [include]):

```bash
# Check .gitconfig
head -10 ~/.gitconfig

# If no [include], update dotfiles
cd ~/dotfiles && git pull
```

## Configuration Reference

### Delta (diff viewer)

| Setting | Value | Description |
|---------|-------|-------------|
| `core.pager` | delta | Use delta as diff viewer |
| `interactive.diffFilter` | delta --color-only | Colored diff for interactive staging |
| `delta.navigate` | true | Navigate between diff sections with n/N |
| `delta.dark` | true | Dark theme |

### Diff

| Setting | Value | Description |
|---------|-------|-------------|
| `diff.algorithm` | histogram | Smarter diff algorithm (improved over default myers) |
| `diff.colorMoved` | plain | Color-highlight moved code blocks |
| `diff.mnemonicPrefix` | true | Use i/w/c (index/worktree/commit) instead of a/b |
| `diff.renames` | true | Detect and display file renames |

### Merge

| Setting | Value | Description |
|---------|-------|-------------|
| `merge.conflictstyle` | zdiff3 | Show original code during conflicts (3-way merge) |

### Push/Fetch/Pull

| Setting | Value | Description |
|---------|-------|-------------|
| `push.default` | simple | Push current branch to same-named remote branch |
| `push.autoSetupRemote` | true | Auto-setup upstream on first push |
| `push.followTags` | true | Auto-push local tags |
| `fetch.prune` | true | Delete local branches removed from remote |
| `fetch.pruneTags` | true | Delete tags removed from remote |
| `pull.rebase` | true | Rebase instead of merge on pull |

### Rebase

| Setting | Value | Description |
|---------|-------|-------------|
| `rebase.autoSquash` | true | Auto-squash `fixup!` commits |
| `rebase.autoStash` | true | Auto-stash before rebase, auto-unstash after |
| `rebase.updateRefs` | true | Update stacked branches during rebase |

### Rerere (Reuse Recorded Resolution)

| Setting | Value | Description |
|---------|-------|-------------|
| `rerere.enabled` | true | Record and reuse conflict resolutions |
| `rerere.autoupdate` | true | Auto-apply recorded resolutions |

### Branch/Tag Display

| Setting | Value | Description |
|---------|-------|-------------|
| `column.ui` | auto | Column display for branch list |
| `branch.sort` | -committerdate | Sort branches by most recent commit |
| `tag.sort` | version:refname | Sort tags by semantic version |

### UX Improvements

| Setting | Value | Description |
|---------|-------|-------------|
| `init.defaultBranch` | main | Default branch name for new repositories |
| `help.autocorrect` | 10 | Auto-execute after 1 second on command typo |
| `commit.verbose` | true | Show full diff when editing commit message |

## Verification Commands

### Rerere

```bash
# Create conflict in test repo, resolve, reset, re-merge
# Auto-resolution on second merge indicates it's working
ls .git/rr-cache/  # Directory exists = OK
```

### Diff

```bash
git diff HEAD~1  # Display with histogram algorithm
git diff --color-moved  # Check moved code coloring
```

### Push

```bash
git checkout -b test-branch
git push  # Sets upstream without -u flag
```

### Rebase

```bash
# Pull with uncommitted changes
echo "test" >> file.txt
git pull  # Auto stash/unstash
```

### Branch Display

```bash
git branch  # Most recent commit order, column display
git tag     # Semantic version order
```

### Autocorrect

```bash
git stauts  # → Executes git status after 1 second
```

## Git Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `git secrets` | `gitleaks detect --verbose` | リポジトリ全体の秘密情報スキャン |
| `git absorb` | `git-absorb --and-rebase` | 変更を自動で正しいコミットにfixup + rebase |

### git secrets

[gitleaks](https://github.com/gitleaks/gitleaks) でリポジトリ履歴全体をスキャン。AWS鍵、GitHub PAT、Slack webhook等を検出。

```bash
git secrets                          # 全履歴スキャン
gitleaks protect --staged --verbose  # ステージ済みのみ (pre-commit用)
```

### git absorb

[git-absorb](https://github.com/tummychow/git-absorb) でステージ済みの変更を自動的に適切なコミットに fixup。`rebase.autoSquash = true` と組み合わせて使用。

```bash
git add -p       # 修正をステージ
git absorb       # 自動fixup + rebase
```

## forgit (fzf-powered Git)

[forgit](https://github.com/wfxr/forgit) は fzf を使った Git 操作のインタラクティブ強化プラグイン。sheldon 経由でインストール。

### Stash 操作

| コマンド | 動作 | 提供元 |
|----------|------|--------|
| `gsh "説明"` | 名前付き stash 作成 | abbreviation (`git stash push -m`) |
| `gsp` | 最新 stash を即 pop | abbreviation |
| `gss` | fzf stash ブラウザ (preview + pop/apply/drop) | forgit |
| `gspu` | fzf でファイル選択して stash push | forgit (renamed) |

`gss` のキーバインド:

| キー | 動作 |
|------|------|
| `enter` | stash 詳細表示 |
| `alt-p` | pop (適用+削除) → リスト再読み込み |
| `alt-a` | apply (適用、stash は残す) → リスト再読み込み |
| `alt-d` | drop (削除) → リスト再読み込み |
| `ctrl-y` | stash ref をクリップボードにコピー |

### その他の forgit コマンド

| コマンド | 動作 |
|----------|------|
| `ga` | fzf で diff preview 見ながら interactive add |
| `gd` | fzf で interactive diff viewer |
| `glo` | fzf で interactive git log |
| `gcb` | fzf で branch checkout |
| `gclean` | fzf で interactive clean |
| `gbl` | fzf で interactive blame |

### 設定

```bash
# common/zsh/.zshrc.common
export forgit_stash_push="gspu"   # gsp (stash pop abbreviation) との衝突回避
export FORGIT_STASH_FZF_OPTS='...' # stash ブラウザのキーバインド
```

### abbreviation との共存

- forgit は zsh-abbr より前に sheldon で読み込まれる
- abbreviation が同名で定義されている場合は abbreviation が優先される
- `ga`, `gd` は abbreviation を削除し forgit の関数を直接使用

## ghq (Repository Management)

[ghq](https://github.com/x-motemen/ghq) はリモートリポジトリをローカルに統一的なディレクトリ構造で管理するツール。

### 設定

| Setting | Value | Description |
|---------|-------|-------------|
| `ghq.root` | `~/ghq` | リポジトリの保存先ディレクトリ |

### ディレクトリ構造

```
~/ghq/
├── github.com/
│   ├── user/repo-a/
│   └── user/repo-b/
└── gitlab.com/
    └── user/repo-c/
```

### 基本コマンド

```bash
# リポジトリを取得
ghq get https://github.com/user/repo

# リポジトリ一覧を表示
ghq list

# リポジトリを新規作成
ghq create repo-name

# リポジトリのルートパスを表示
ghq root
```

### シェル統合

`repo` 関数（`common/zsh/.zshrc.common` で定義）で ghq + fzf によるリポジトリ移動が可能:

```bash
# fzf でリポジトリを選択して cd
repo

# 初期フィルタ付きで起動
repo my-project
```

- `ghq` と `fzf` の両方がインストールされている場合のみ有効
- fzf preview で README.md またはディレクトリ内容を表示
- `cd` は zoxide ラップ版を使用するため、訪問したリポジトリが zoxide の frecency DB に蓄積される

### 略語（zsh-abbr）

| 略語 | 展開後 | 説明 |
|------|--------|------|
| `gq` | `ghq get` | リポジトリを取得 |
| `gql` | `ghq list` | リポジトリ一覧 |
| `gqc` | `ghq create` | リポジトリを新規作成 |

## Global Ignore

`~/.config/git/ignore` (XDG-compliant, Git auto-recognizes):

```
# macOS
.DS_Store

# Claude Code local settings
**/.claude/settings.local.json
```

**Note**: No need to configure `core.excludesfile`. Git automatically reads `~/.config/git/ignore`.

## Related Documentation

- [1Password Integration](./1password-integration.md) - Detailed 1Password CLI configuration
