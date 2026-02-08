# Neovim トラブルシューティング

## SIGKILL (exit 137) でクラッシュ

**日付**: 2026-01-30
**環境**: macOS (Apple Silicon), nvim 0.11.5, LazyVim

### 症状

- nvim が起動直後に閉じる、またはファイルを開くと SIGKILL (exit 137) で死ぬ
- `:` を押しても反応しない（noice.nvim cmdline フリーズ）
- `nvim --clean` では正常動作

### 原因

3つの問題が同時発生していた:

1. **omnisharp (LazyVim extra)** が起動時に SIGKILL を引き起こしていた
2. **treesitter パーサー破損** — `vim.so`, `markdown.so`, `rust.so` 等のコンパイル済みパーサーが壊れ、該当ファイルタイプを開くとネイティブコードがクラッシュ
3. **treesitter クエリ不整合** — `nvim-treesitter` の `vim` 言語クエリが `"tab"` ノードタイプを参照しているが、パーサーが対応していなかった。これにより `noice.nvim` の cmdline ハイライトが壊れ、全インタラクティブ操作が不能に

### 修正手順

```bash
# 1. omnisharp を無効化 (lazy.lua で該当行をコメントアウト)
# { import = "lazyvim.plugins.extras.lang.omnisharp" },

# 2. treesitter パーサーを全削除・再コンパイル
rm -rf ~/.local/share/nvim/site/parser/
nvim --headless -c "TSUpdate" -c "sleep 60" -c "qa!"

# 3. vim パーサーを個別に再インストール (noice.nvim cmdline 修正)
nvim --headless -c "TSInstall! vim" -c "sleep 30" -c "qa!"

# 4. (必要に応じて) luac キャッシュクリア
rm -rf ~/.cache/nvim/luac
```

### 診断方法メモ

```bash
# ファイルタイプ別にクラッシュを確認
nvim --headless -c "edit /tmp/test.md" -c "sleep 3" -c "qa!"
echo $?  # 137 ならクラッシュ

# treesitter パーサーが原因か確認 (パーサー削除で開けるなら確定)
rm -rf ~/.local/share/nvim/site/parser/
nvim --headless -c "edit /tmp/test.md" -c "sleep 3" -c "qa!"

# noice.nvim のエラーログ確認
cat ~/.local/state/nvim/noice.log
```

### 関連変更

- `lazy.lua`: omnisharp コメントアウト
- mason の omnisharp パッケージも削除済み (`~/.local/share/nvim/mason/packages/omnisharp`)

---

## Lazy.nvim が "You have local changes" で更新を拒否する

**日付**: 2026-02-09

### 症状

`:Lazy sync` 実行時に以下のエラーが表示され、プラグインが更新されない:

```
You have local changes in `/path/to/nvim/lazy/plugin-name`:
  * path/to/modified/file.lua
Please remove them to update.
```

### 原因

プラグインのソースファイルがローカルで変更されている。以下のケースで発生:

1. **パッチ適用方式の変更後**: dotfiles で以前 `init` フックでソースファイルを直接変更していたが、ランタイムパッチ方式に変更した場合、古い変更が残っている
2. **手動でのデバッグ・修正**: プラグインのコードを直接編集した場合

### 修正手順

```bash
# 方法1: 変更を破棄
git -C ~/.local/share/nvim/lazy/plugin-name restore path/to/modified/file.lua

# 方法2: プラグイン全体を再インストール
# Lazy.nvim の画面で該当プラグインにカーソルを合わせ:
# x (削除) → I (インストール)

# 方法3: lazy ディレクトリごと削除して全再インストール
rm -rf ~/.local/share/nvim/lazy/plugin-name
nvim  # 自動で再インストールされる
```

### 予防策

プラグインのソースファイルを直接変更するパッチは避け、`config` 関数内でのランタイムオーバーライド（monkey-patch）を使用する。

参考: `docs/patches/codediff-directory-collapse.md`
