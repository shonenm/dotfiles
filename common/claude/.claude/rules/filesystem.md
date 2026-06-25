# Filesystem

- 一時ファイルは literal `/tmp` を使わない。`$TMPDIR` / `mktemp`(TMPDIR 尊重)を使用する
- 永続キャッシュ・状態は XDG (`$XDG_CACHE_HOME` / `$XDG_STATE_HOME` / `$XDG_RUNTIME_DIR`) を使用する
- docker 共有は `$DOTFILES_SHARED_DIR` を使用する

`/tmp` への直接アクセスは PreToolUse フック (block-tmp.sh) で deny される。
