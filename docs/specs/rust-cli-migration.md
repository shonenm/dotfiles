# Rust 置換 全体設計 — tools/ workspace (ai-usage / wt / pomodoro)

戦略 doc の Rust 層（配布 native binary）を 3 ターゲットで完結させる設計。
ai-usage の詳細は [ai-usage-rust-pilot.md](ai-usage-rust-pilot.md)。本 doc は wt / pomodoro の設計と、3 binary を束ねる workspace / install / 切替計画を定義する。

設計日: 2026-07-18

## 実装完了 (2026-07-18)

全 7 マイルストーン完了。M0 pomodoro → M1-M3 ai-usage (claude/gemini/cursor/codex) →
M4 wt → M5 install 導線 → M6 consumer 切替 + 旧 bash 8 ファイル削除 → M7 doc。
各段階で bash 版との byte-parity を確認済み。設計からの差分:

- **rusqlite → sqlite3 CLI**: libsqlite3-sys 0.38 が unstable feature (`cfg_select`) 依存で
  rustc 1.92 build 不可。cursor の IDE sqlite fallback は sqlite3 CLI へ shell-out に変更
  (keychain/secret-tool と同じ方針、重い build 依存も回避)
- **fs4 → std File::lock**: codex の排他ロックは std の `File::lock` (1.89 安定化) で足り、
  fs4 依存は削除
- **cursor は独立ファイルでなく symlink**: (Phase 0-4 で判明済み) sidebar のみが consumer
- **.wt-config は TOML 化**: 未配置時は組込みデフォルト維持で挙動不変
- **ureq は json feature 無効**: 送信は serde_json + `.send()` で body 構築

依存: ureq(rustls) / serde / serde_json / jiff / base64 / toml。標準ライブラリ優先で
fs4・rusqlite は不採用。

## スコープ確定

| binary | 置換対象 (bash) | 行数 | effort |
|--------|----------------|------|--------|
| `ai-usage` | tmux-{claude,codex,gemini,cursor}-usage.sh + cursor-auth-token.sh | ~980 | M |
| `wt` | scripts/wt + scripts/wt-lib.sh | ~400 | L |
| `pomodoro` | scripts/pomodoro.sh | ~194 | S |

これで Rust 置換は完了とする。ralph-crew は Go（Phase 2）、これ以上の Rust 拡大はしない。

## Workspace 構成

```
tools/
  Cargo.toml           — [workspace] members = ["ai-usage", "wt", "pomodoro"]
  ai-usage/            — ai-usage-rust-pilot.md 参照
  wt/
    src/
      main.rs          — subcommand dispatch
      git.rs           — worktree porcelain parse / repo 情報
      tmux.rs          — window 操作 (shell-out)
      sync.rs          — ignored files の symlink/copy 同期 (.wt-config 対応)
  pomodoro/
    src/main.rs        — 単一ファイル（state machine + file I/O のみ）
```

- workspace で `target/` と `Cargo.lock` を共有。install は `cargo build --release` 一発で 3 binary
- edition 2024 / stable toolchain。rust は installer で bootstrap 済み

## wt 設計

### 現契約（維持）

- user-facing: `wt new <branch> [base]` / `wt checkout <pr>` / `wt list` / `wt delete <branch>` / `wt clean`
- worktree パス規約: `${main}--wt--${branch//\//-}`、tmux window 名: `${repo}#${branch}`
- data は stdout / status は stderr（`path=$(wt new ...)` でパスだけ capture 可能）
- `.wt-config`（main worktree 直下、Phase 0-6 で導入）による symlink_dirs / skip_dirs override
- ignored file 同期: symlink 対象 / skip 対象 / copy（macOS clonefile `cp -c` / Linux `--reflink=auto`）の 3 分類

### 重要な追加要件: ralph が wt-lib.sh を source している

`ralph-orchestrate` / `ralph-schedule` / `ralph-schedule-exec.sh` が lib 関数を直接使用:
`wt_create` `wt_delete` `wt_exists` `wt_path` `wt_main_worktree` `wt_window_name` `wt_copy_ignored` `wt_check_git`

2 実装並存（binary + lib）は drift の再生産なので、binary に plumbing subcommand を追加して ralph を shell-out に切り替え、wt-lib.sh は削除する:

```
wt path <branch>          # worktree パスを print (wt_path)
wt exists <branch>        # exit code で判定 (wt_exists)
wt root                   # main worktree パス (wt_main_worktree; git repo 外なら非0 = wt_check_git 代用)
wt window-name <branch>   # tmux window 名 (wt_window_name)
wt sync-ignored <src> <dst>  # ignored 同期 (wt_copy_ignored)
wt new <branch> [base]    # 作成 + パスを stdout に print (wt_create 相当に変更)
wt delete <branch>        # (wt_delete)
```

- `wt new` は現 CLI ではパスを捨てているが、lib の wt_create 同様 stdout にパスを出す仕様に統一（既存の手動利用に影響なし、ralph 移行が単純化）
- `wt_info/success/error` は単なるログ helper。ralph 側に 3 行の関数として残す（wt の責務ではない）

### 実装方針

- git 操作: `git worktree list --porcelain` 等を `std::process::Command` で shell-out し構造体に parse（Phase 0-6 の porcelain parser を型付きで再現）。libgit2(git2 crate) は不使用 — worktree add/remove は CLI が正であり、lib 化は依存だけ増える
  `// ponytail: shell-out git; git2 は必要になったら`
- tmux 操作も shell-out（`tmux new-window` 等、$TMUX 無しでは skip — 現挙動維持）
- copy 分類ロジック（symlink/skip/copy + glob マッチ）を enum + 純粋関数にして unit test を付ける — これが wt を Rust 化する学習核心
- `wt checkout` の PR 情報は `gh pr view --json` へ shell-out + serde parse
- 依存: `serde`/`serde_json`（gh 出力 + .wt-config を TOML でなく現行 bash source 形式から **簡易 KEY=(...) parse** はしない — `.wt-config` を **TOML に移行**し `toml` crate で読む。bash 版 .wt-config はまだ利用実績なしのため互換不要）

### .wt-config 形式（TOML 化）

```toml
symlink_dirs = ["node_modules", ".venv", "packages/*/node_modules"]
skip_dirs = [".mypy_cache", ".turbo"]
```

未配置時は現行デフォルト（wt-lib.sh にハードコードされていたリスト）を binary 内デフォルトとして維持。

## pomodoro 設計

### 現契約（維持必須 — 外部が state file を直読み）

- CLI: `start [min]` / `pause` / `toggle` / `reset` / `set <min>` / `status`
- state dir: `${XDG_RUNTIME_DIR:-${TMPDIR:-~/.cache}}/sketchybar/pomodoro`
- state files: `state`（running/paused/stopped）, `end_time`（epoch 秒）, `remaining`（秒）, `duration`（秒）
  — **sketchybar の表示 plugin（plugins/pomodoro.sh）がこれらを直接読む**ため、ファイル名・形式・パスは変更不可
- 各操作後に `sketchybar --trigger pomodoro_update`（sketchybar 不在なら無視）
- stdout メッセージ（"Started: 25m 0s" 等）も維持（人間向けだが挙動同一に）

### 実装方針

- 依存ゼロ（std のみ）。`enum State { Running, Paused, Stopped }` + `FromStr/Display` の型付き state machine
- 時刻は `SystemTime`/`UNIX_EPOCH`（ISO parse 不要なので jiff も不要）
- 最小 Rust 練習台として位置づけ、3 binary の中で最初に実装する（M0）

### 消費者の切替

- `aerospace.toml` の 5 keybind（`~/dotfiles/scripts/pomodoro.sh set 25` 等）→ `$HOME/.local/bin/pomodoro set 25`（exec-and-forget は PATH が細いので絶対パス）
- `sketchybarrc` の click_script も同様
- 表示側 `plugins/pomodoro.sh` は sketchybar glue なので bash のまま（戦略 doc の LEAVE AS BASH 通り）

## install 導線（3 binary 共通）

`install-common.sh` の `install_ai_usage` を `install_rust_tools` に一般化:

```bash
install_rust_tools() {
  command_exists cargo || { log_warn "cargo not found, skipping rust tools"; return; }
  log_info "Building rust tools (ai-usage / wt / pomodoro)..."
  if cargo build --release --manifest-path "$DOTFILES_DIR/tools/Cargo.toml"; then
    mkdir -p "$HOME/.local/bin"
    for b in ai-usage wt pomodoro; do
      install "$DOTFILES_DIR/tools/target/release/$b" "$HOME/.local/bin/"
    done
    log_success "rust tools installed"
  else
    log_warn "rust tools build failed (existing bash versions remain until switchover)"
  fi
}
```

- build 失敗は degrade（run_step が収集、installer 継続）
- `tools/target/` は .gitignore に追加

## 切替順序とゲート

| 順 | 作業 | ゲート |
|----|------|--------|
| M0 | workspace + pomodoro 実装 | CLI 全 subcommand の出力/state file が bash 版と一致（両実装を同一 state dir で交互実行して確認）。aerospace/sketchybarrc 切替は parity 後 |
| M1-M3 | ai-usage（claude → gemini/cursor → codex）| ai-usage-rust-pilot.md のゲート |
| M4 | wt 実装（porcelain/分類ロジック + plumbing subcommand） | unit test + 実 repo で new/list/delete/clean が bash 版と同挙動 |
| M5 | ralph 3 スクリプトを wt shell-out に切替、wt-lib.sh 削除 | ralph-orchestrate/schedule の dry-run が通る |
| M6 | install_rust_tools 導線 + 全消費者切替（sidebar / aerospace / sketchybarrc） + 旧 bash 削除 | mac + Linux/container E2E |
| M7 | doc 更新（strategy doc の Phase 完了マーク） | - |

注意: `wt` は scripts/ (PATH 上) と ~/.local/bin で名前が衝突する。切替は「binary 配置と scripts/wt 削除を同一コミット」で行い、途中状態を作らない。

## リスク

- wt は ralph の依存になるため、切替後は「binary 必須」化する（non-load-bearing 原則の例外）。緩和: M5 を最後まで遅らせ、binary が実環境で安定してから ralph を切替える。セッション本体（statusline/hook）には依然として無関係
- pomodoro の XDG_RUNTIME_DIR は tmpfs で reboot 時に消える — 現挙動と同一（維持）
- .wt-config の TOML 化は bash 版と非互換だが、Phase 0-6 導入直後で利用実績ゼロのため互換層は作らない
