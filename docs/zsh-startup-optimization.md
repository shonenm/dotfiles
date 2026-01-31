# Zsh 起動速度の最適化

tmux pane 起動時の遅延を解消するために実施した最適化の記録。

## 計測結果

| 状態 | login shell | non-login shell (tmux pane) |
|------|------------|-----------|
| 最適化前 | ~1.3s | ~1.3s |
| 最適化後 | **180ms** | **150ms** |

## ボトルネック分析 (zprof)

`zmodload zsh/zprof` で計測した主要ボトルネック:

| 時間(ms) | 関数 | 原因 |
|----------|------|------|
| 263 | `compinit` | 補完関数 836 個をフルスキャン（キャッシュなし） |
| 79 | `compdump` | compinit 内でダンプファイル再生成 |
| 77 | `compdef` (836回) | 各ツールの eval 内で compdef が呼ばれる |
| 30 | `zsh-abbr` (97回) | 71 個の略語を 1 個ずつ登録 |
| 20 | `_mise_hook` | mise activate のフック |

## 実施した修正

### 1. tmux auto-reload 削除 (~560ms)

`.zshrc.common` で pane 起動毎に `tmux source tmux.conf` を実行していた。
設定変更時は `prefix+r` で手動リロードすれば十分。

```bash
# 削除した箇所 (.zshrc.common)
if command -v tmux >/dev/null 2>&1 && [ -n "$TMUX" ]; then
  tmux source ~/.config/tmux/tmux.conf 2>/dev/null
fi
```

### 2. compinit キャッシュ化 (~250ms)

`.zcompdump` が 24 時間以内なら `compinit -C` でキャッシュを再利用。
zsh コミュニティの標準パターン（glob qualifier `(#qN.mh+24)`）。

```bash
# common/zsh/.zshrc.common
autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit        # 24h 経過 → フルリビルド
else
  compinit -C     # キャッシュ利用（compaudit スキップ）
fi
```

### 3. gh completion を静的ファイル化 (~140ms)

毎回 `eval "$(gh completion -s zsh)"` を実行する代わりに、静的ファイルを fpath に配置。

```bash
# common/zsh/.zshrc.common
[[ -d "$HOME/.zsh/completions" ]] && fpath=("$HOME/.zsh/completions" $fpath)
```

gh アップグレード時に再生成が必要:

```bash
mkdir -p ~/.zsh/completions
gh completion -s zsh > ~/.zsh/completions/_gh
```

### 4. sheldon + zsh-defer でプラグイン遅延読み込み (~35ms)

sheldon 公式推奨の `zsh-defer` (romkatv 製) を導入。
syntax-highlighting と autosuggestions を遅延読み込みに変更。

```toml
# common/sheldon/.config/sheldon/plugins.toml
[templates]
defer = "{% for file in files %}zsh-defer source \"{{ file }}\"\n{% endfor %}"

[plugins.zsh-defer]
github = "romkatv/zsh-defer"

[plugins.zsh-syntax-highlighting]
github = "zsh-users/zsh-syntax-highlighting"
apply = ["defer"]

[plugins.zsh-autosuggestions]
github = "zsh-users/zsh-autosuggestions"
apply = ["defer"]
```

zsh-abbr は compdef を使うため即時読み込みのまま維持。

### 5. brew shellenv 重複排除 (~20ms)

`.zprofile` と `.zshrc.local` の両方で `eval "$(/opt/homebrew/bin/brew shellenv)"` を実行していた。
`.zprofile` 側のみに統一。

### 6. Homebrew Node fallback パス削除

mise で node を管理しているため、ハードコードされた `/opt/homebrew/Cellar/node/23.2.0/bin` を削除。

### 7. .zprofile の .zshrc 二重ロード解消 (~400ms)

`.zprofile` 末尾で `source "$HOME/.zshrc"` していたため、login shell 時に .zshrc が 2 回実行されていた。

zsh の login + interactive shell ロード順:
```
.zshenv → .zprofile → .zshrc → .zlogin
```

zsh 本体が `.zshrc` を自動でロードするため、`.zprofile` 内の source は冗長。削除。

### 8. tmux pane を non-login shell に変更 (~30ms)

tmux はデフォルトで login shell (`-zsh`) を起動するため、pane 毎に `.zprofile` が実行される。
親 tmux プロセスが既に PATH 等を設定済みなので不要。

```tmux
# common/tmux/.config/tmux/tmux.conf
set -g default-command "${SHELL}"  # non-login shell
```

pane 起動時は `.zshenv` → `.zshrc` のみが実行され、`.zprofile` をスキップ。

## 変更ファイル一覧

| ファイル | 変更内容 |
|----------|----------|
| `common/zsh/.zshrc.common` | tmux reload 削除、compinit キャッシュ化、gh completion 静的化 |
| `common/sheldon/.config/sheldon/plugins.toml` | zsh-defer 追加、プラグイン遅延読み込み |
| `mac/zsh/.zshrc.local` | brew shellenv 重複削除、Node fallback 削除 |
| `common/zsh/.zprofile` | .zshrc 二重ロード行を削除 |
| `common/tmux/.config/tmux/tmux.conf` | `default-command "${SHELL}"` 追加 |

## 計測方法

```bash
# 起動時間
time zsh -i -c exit          # non-login shell (tmux pane)
time zsh -l -i -c exit       # login shell

# プロファイリング
zsh -c 'zmodload zsh/zprof; source ~/.zshenv; source ~/.zprofile; source ~/.zshrc; zprof'
```
