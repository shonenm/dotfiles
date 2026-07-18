# Phase 1 設計 — ai-usage (Rust パイロット)

`tmux-{claude,codex,gemini,cursor}-usage.sh` + `cursor-auth-token.sh`（計 ~980 行の bash+python3）を単一 Rust binary `ai-usage` に統合する。
[language-refactor-strategy.md](language-refactor-strategy.md) の Phase 1。目的は学習（HTTP / OAuth refresh / file-lock / Keychain / sqlite）+ 重複排除。cargo-in-install.sh の導線をここで実証し、Phase 2 (ralph-crew Go 化) の前提を作る。

設計日: 2026-07-18

## ゴール / 非ゴール

- ゴール: 4 プロバイダの usage 取得を 1 binary に統合。既存の出力契約・キャッシュ形式・fail-open 挙動を完全維持
- 非ゴール: 表示フォーマット変更、新機能、daemon 化（cold-run + file cache の現行モデルを維持）、tmux-agent-sidebar 側の再設計

## 現状棚卸し（5 スクリプトの共通構造と差分）

全スクリプト共通のパイプライン:

```
cache 有効(5min TTL, mtime)? → cache から render
→ fail backoff (60s)? → placeholder
→ token 取得 → HTTP fetch (5s timeout) → JSON parse → cache 書込 → render
```

出力契約（tmux-agent-sidebar.sh `usage_section` が消費）:
- 1 行 = 1 ウィンドウ: `ICON\x1fLABEL\x1fGAUGE\x1fPCT\x1fREMAINING`（US=0x1f 区切り）
- データ無し: `ICON\x1f--`
- GAUGE は 9 段階 bar（` ▁▂▃▄▅▆▇█`、0%=空白・低%でも最低 ▁）、REMAINING は `Nm`/`NhMMm`/`NdNh` 形式

プロバイダ差分:

| provider | token 源 | refresh | API | parse の要点 |
|----------|---------|---------|-----|-------------|
| claude | mac: Keychain `Claude Code-credentials` / linux: `~/.claude/.credentials.json` | なし | GET `api.anthropic.com/api/oauth/usage`（`anthropic-beta: oauth-2025-04-20`） | five_hour/seven_day の utilization + resets_at (ISO) |
| codex | `~/.codex/auth.json`（両 OS プレーンファイル） | あり: `auth.openai.com/oauth/token`、JWT exp 判定、fcntl 排他ロック、tmp+chmod+rename の atomic write、401 時 1 回だけ retry | GET `chatgpt.com/backend-api/wham/usage`（`ChatGPT-Account-Id` header、account_id は tokens.account_id か id_token JWT claim） | primary/secondary window から `limit_window_seconds ≈ 7d` で weekly 判別。cache は `v2\|...` 形式 |
| gemini | `~/.gemini/oauth_creds.json`（access_token + expiry_date ms） | なし（client secret を持たないため。期限切れは placeholder で CLI 再起動を促す） | POST `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`（project は `GOOGLE_CLOUD_PROJECT` > `~/.gemini/projects.json`、空でも可） | buckets を used 降順 sort し top2 |
| cursor | 解決 ladder: env `CURSOR_AUTH_TOKEN`/`CURSOR_API_KEY` → mac Keychain `cursor-access-token` → linux `secret-tool` → Cursor IDE `state.vscdb` (sqlite) | なし | POST `api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`（Connect protocol）、fallback GET `/auth/usage` | planUsage の includedSpend/limit、fallback は maxRequestUsage bucket の最大 |

env override（テスト・container 用、維持必須）: `CODEX_USAGE_CACHE` / `CODEX_AUTH_FILE` / `CODEX_REFRESH_URL` / `CODEX_USAGE_URL` / `CODEX_CLIENT_ID` / `CURSOR_API_BASE` / `GOOGLE_CLOUD_PROJECT`。

`cursor-auth-token.sh` の消費者は `tmux-cursor-usage.sh` のみ → binary の内部モジュールに吸収し、独立スクリプトは最終的に削除。

## CLI 契約

```
ai-usage <claude|codex|gemini|cursor>
```

- stdout に既存と同一の US 区切りレコードを出力、exit 0（データ無しでも placeholder を出して 0。呼び出し側の tmux/sidebar を絶対に壊さない = fail-open）
- subcommand 以外の引数・flag は当面なし（YAGNI）
- 配置: `~/.local/bin/ai-usage`

## 不変条件（パリティの定義）

1. 出力レコードのバイト一致（同一入力 JSON に対して）
2. キャッシュファイルのパス・形式を維持（`claude_usage`、`codex_usage` の `v2|` 形式、`gemini_usage`、`cursor_usage`）— 移行期間中 bash 版と読み書き互換
3. fail backoff（`.fail` ファイル、60s）と 5min TTL の挙動維持
4. codex の atomic write（tmp → 元ファイルの mode 継承 → rename）と排他ロックの維持
5. secret を stdout 以外に出さない（トークンをログ・エラーメッセージに含めない）

## クレート構成

```
tools/ai-usage/
  Cargo.toml
  src/
    main.rs          — subcommand dispatch（std::env::args で match、clap 不使用）
    cache.rs         — TTL cache + fail backoff（mtime ベース、既存ファイル互換）
    render.rs        — bar gauge / remaining humanize / US 区切りレコード生成
    providers/
      mod.rs         — Provider trait（fetch → parse → CacheEntry）
      claude.rs
      codex.rs       — refresh flow（lock / atomic write / JWT decode / retry-once）
      gemini.rs
      cursor.rs      — token ladder（env → keychain → secret-service → sqlite）
```

## 依存クレートと選定理由

| 用途 | crate | 理由 |
|------|-------|------|
| HTTP | `ureq` (rustls) | 同期 CLI に async runtime は不要。rustls で openssl リンク回避 = musl cross が素直。reqwest+tokio は Phase 2 の daemon 領域 |
| JSON | `serde` + `serde_json` | 標準。学習の中核 |
| 日時 | `jiff` | ISO8601 parse + duration。モダンで学習価値が高い |
| file lock | `fs4` | flock の維持（fs2 の保守フォーク） |
| JWT payload | `base64` | 署名検証せず claim を読むだけ（bash 版と同じ）。jsonwebtoken は過剰 |
| sqlite | `rusqlite` (bundled) | cursor IDE fallback。bundled で musl cross 可 |
| error | `thiserror` + `anyhow` | provider エラーを enum で型付け（学習）、main は anyhow |

Keychain / secret-service は crate を使わず `security` / `secret-tool` へ shell-out（`std::process::Command`）。bash 版と同一挙動で、platform 依存クレートのビルド複雑性を避ける。
`// ponytail: shell-out keychain; security-framework crate は必要になったら`

## テスト

- unit: 各 provider の parse（実 API レスポンスを fixture 化）、render の bar/remain 境界値、cache TTL/backoff、codex JWT decode
- integration: codex は env override で mock server を立てて refresh flow を通す（`CODEX_REFRESH_URL`/`CODEX_USAGE_URL` が既にこのために存在）
- parity: 実環境で bash 版と rust 版を並走させ、レコード出力を diff（キャッシュ互換なので同一 cache を読ませて比較）

## install 導線（cargo-in-install.sh の実証）

`scripts/install-common.sh` に追加（mac/linux 共通、Phase 0-1 の共通化に乗る）:

```bash
install_ai_usage() {
  command_exists cargo || { log_warn "cargo not found, skipping ai-usage"; return; }
  log_info "Building ai-usage..."
  if cargo build --release --manifest-path "$DOTFILES_DIR/tools/ai-usage/Cargo.toml"; then
    mkdir -p "$HOME/.local/bin"
    install "$DOTFILES_DIR/tools/ai-usage/target/release/ai-usage" "$HOME/.local/bin/"
    log_success "ai-usage installed"
  else
    log_warn "ai-usage build failed (usage widgets fall back to placeholder)"
  fi
}
```

- build 失敗時は ai-usage だけが欠ける degrade（run_step が失敗を収集、installer は継続）— ハード制約遵守
- container: 当面は各環境で cargo build（rust は既に bootstrap 済）。cross-compile 配布（`cargo-zigbuild` + musl）は「container に cargo を入れたくない」実需が出た時に導入
  `// ponytail: per-env build; prebuilt 配布は必要になってから`

## 切替とロールバック

1. binary 実装 + テスト（既存 .sh は無変更で共存。キャッシュ互換なので並走可）
2. `tmux-agent-sidebar.sh` の loop を `command -v ai-usage` があれば binary、なければ既存 .sh に分岐（移行期間のみの分岐。binary 未導入環境 = container を壊さないため）
3. mac + Linux + container で E2E 確認（sidebar 表示が bash 版と一致）
4. 全環境で確認後: 旧 5 スクリプト削除 + sidebar の分岐を binary 直呼びに一本化 + 本 doc と戦略 doc を更新

ロールバックは sidebar の分岐を戻すだけ（.sh は 4 まで残る）。

## 学習マップ（このパイロットで身につくもの）

| テーマ | 実装箇所 |
|--------|---------|
| HTTP client / TLS | ureq + rustls、timeout、header 組み立て |
| OAuth refresh flow | codex: JWT exp 判定 → refresh POST → token 保存 → retry-once |
| file lock / atomic write | codex: fs4 flock + tmp/rename、mode 継承 |
| OS 資格情報 | claude/cursor: Keychain・secret-service・sqlite の解決 ladder |
| serde 設計 | 4 種の API スキーマ + 欠損 field の Option 処理 |
| エラー型設計 | thiserror enum + fail-open への収束（全エラー → placeholder） |
| テスト | fixture parse test、mock server integration |

## マイルストーン

完了（2026-07-18）。本 doc は ai-usage 単体の設計だが、実行は wt/pomodoro と統合した
[rust-cli-migration.md](rust-cli-migration.md) の M0-M7 で行った。ai-usage 該当分の対応:

| M (本 doc) | 実績 | 状態 |
|-----------|------|------|
| M1 skeleton + render + cache + claude | rust-cli M1 (commit c31c03a)。単一 jq→`\x1f` cache/render 基盤 + claude | 完了 |
| M2 gemini + cursor | rust-cli M2 (d46fc78)。cursor sqlite は rusqlite 断念 → sqlite3 CLI shell-out | 完了 |
| M3 codex (refresh / lock / atomic write) | rust-cli M3 (759b960)。fs4 断念 → std `File::lock`。mock server で refresh flow E2E | 完了 |
| M4 install 導線 + sidebar 切替 + E2E | rust-cli M5/M6 (db3892f/f0a796f)。sidebar は「分岐」でなく直接 ai-usage 呼び出しに置換 | 完了 |
| M5 旧スクリプト削除 + doc | rust-cli M6/M7 (f0a796f/df31c53)。usage 4 本 + cursor-auth-token 削除 | 完了 |

設計から変わった点は [rust-cli-migration.md#実装完了](rust-cli-migration.md) に集約（rusqlite→sqlite3 CLI、fs4→std、sidebar 直呼び）。

## リスク

- API スキーマは全て非公式（wham/usage、retrieveUserQuota、api2.cursor.sh）。上流変更で壊れる点は bash 版と等リスク。fail-open で表示が `--` になるだけ
- rusqlite bundled の初回ビルドがやや重い（数十秒）。cursor IDE fallback を使わない環境でもビルドは走る — 許容
- musl cross は M4 以降の実需が出るまで着手しない
