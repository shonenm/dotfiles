# Zsh 非インタラクティブシェル対応

Claude Code などのツールが zsh を起動する際、`.zshrc` が読み込まれてビルトインコマンドが上書きされる問題への対策。

## 問題

非インタラクティブシェル（`zsh -c 'command'`）でも `.zshrc` が読み込まれ、以下のエイリアス/関数がビルトインを上書きしてしまう：

| コマンド | 上書き先 | 影響 |
|----------|----------|------|
| `cd` | zoxide | ディレクトリ変更の挙動が変わる |
| `rm` | rip | ファイル削除がゴミ箱へ移動に |
| `grep` | rg | 出力フォーマットが異なる |
| `find` | fd | 引数の構文が異なる |
| `sed` | sd | 引数の構文が異なる |
| `chpwd()` | ls 実行 | cd 時に不要な出力が発生 |

## 解決策

`[[ -o interactive ]] || return` ガードにより、インタラクティブ専用コードを非インタラクティブシェルで実行しないようにする。

### 変更ファイル

| ファイル | 変更内容 |
|----------|----------|
| `common/zsh/.zshrc.common` | 非インタラクティブ安全セクションとインタラクティブ専用セクションに分離 |
| `mac/zsh/.zshrc.local` | ガード追加 |
| `linux/zsh/.zshrc.local` | ガード追加（TERM fallback 後） |

### .zshrc.common の構造

```bash
# =====================================================
# Non-interactive safe section
# (PATH, environment variables - needed by scripts)
# =====================================================
export XDG_CONFIG_HOME=...
export PATH=...
export FZF_DEFAULT_OPTS=...

# =====================================================
# Interactive-only section
# (aliases, completions, prompts, hooks)
# =====================================================
[[ -o interactive ]] || return

# mise/direnv hooks
# compinit
# aliases (ls, grep, rm, find, sed, etc.)
# eval (starship, zoxide)
# chpwd hook
# 関数定義
```

## 検証方法

```bash
# 非インタラクティブシェルでエイリアスが無効
zsh -c 'type cd'   # → "cd is a shell builtin"
zsh -c 'type rm'   # → "rm is /bin/rm"
zsh -c 'type grep' # → "grep is /usr/bin/grep"

# インタラクティブシェルでエイリアスが有効
zsh -i -c 'type cd'   # → zoxide function
zsh -i -c 'type rm'   # → rip alias
zsh -i -c 'type grep' # → rg alias
```

## 注意事項

- **mise/direnv**: インタラクティブセクションに移動。非インタラクティブシェルでは環境変数の自動切り替えは不要
- **PATH 設定**: 非インタラクティブセクションに残す。スクリプトからツールを呼び出せるようにするため
- **FZF_DEFAULT_OPTS**: 非インタラクティブセクションに残す。export のみでシェルの動作に影響しないため
