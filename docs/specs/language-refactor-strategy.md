# 言語リファクタ戦略 — dotfiles

適材適所な言語への書き換えによる perf 改善・可読性向上・拡張性・学習を目的とした調査結果と方針。
13 エージェント（6 クラスタ × 分析 → 懐疑批判 + 統合、Web 調査込み）で約 40 スクリプトを精査した結論をまとめる。

調査日: 2026-07-18

## エグゼクティブ判定

最上位制約は「bare な remote Linux / container に `install.sh` で再現できる」こと（CLAUDE.md のポータビリティ規約）。この一点が「Go/Rust に書き換える」提案のほとんどを却下する。

- 書き換えて得をするのは実質 2 本だけ。しかも根拠は performance ではなく **学習 + 保守性**
- perf を書き換え根拠にした主張は全て虚偽だった（60s tick の jq、human-paced hook、background subshell 投函、5 分キャッシュ）。速度は判断材料から除外する
- 最もレバレッジが高いのは書き換えですらなく、**bash のまま重複排除と既存バグ修正**（Phase 0）

## Phase 0 — bash のまま今すぐやる（完了 2026-07-18）

書き換えゼロ。実バグ修正 + 重複排除。全7項目 完了・push 済み（全ファイル shellcheck -S error クリーン）。

| # | 対象 | やること | effort | 状態 |
|---|------|---------|--------|------|
| 0-1 | `scripts/mac.sh` / `scripts/linux.sh` の 8 関数 | バイト一致の重複を `scripts/install-common.sh` に抽出して source。parity drift を根絶。mac.sh/linux.sh 各 -161 行 | S | 完了 |
| 0-2 | `scripts/ai-notify.sh` relay JSON | 書き込みキー `timestamp` → `updated` に改名。`claude-status.sh` は `.updated` を読むため中継が `updated=0` に化ける実バグを修正 | XS | 完了 |
| 0-3 | `scripts/ai-notify.sh` / `scripts/claude-status.sh` | 文字列連結 JSON を `jq -n --arg` 化。project/workspace 名経由の JSON injection を根絶 | S | 完了 |
| 0-4 | statusline | 10 個の jq を単一 jq（`\x1f` 区切り join + read）に集約（fork 10→1）、実装を `scripts/statusline-render.sh` に共有化。claude 実ファイルは fail-open wrapper 化 | S | 完了 |
| 0-5 | `scripts/linux.sh` github-release engine | 33 tools を mise（aqua 25 / ubi 8）へ移行しエンジン撤去。eval-on-data + unauthenticated scrape を根絶 | M | 完了 |
| 0-6 | `scripts/wt` / `scripts/wt-lib.sh` | `wt_clean` / `cmd_list` / `wt_exists` を `--porcelain` 構造 parse に統一、hardcode dir を `.wt-config` override に | S | 完了 |
| 0-7 | 移植性バグ（in-place） | `ralph-session-context.sh:75` の `grep -oP`→POSIX、`dev-tunnel:74` の pgrep anchor 強化 | XS | 完了 |

Phase 0 後、「書き換えないと直らない問題」は事実上ゼロ。以降の書き換えは純粋に学習投資。

### 実装時に判明した当初計画との差分

- **0-4**: cursor 版 statusline は独立ファイルではなく claude への symlink だった（重複ではなく共有済み）。共通本体を `scripts/statusline-render.sh` に集約し、claude 実ファイルを wrapper 化するだけで cursor も自動的に新実装を共有。jq 集約は `@tsv` ではなく `\x1f`（unit separator）区切りにした（tab は whitespace-IFS で空フィールドが潰れるため）
- **0-5**: 当初 mac 汚染（グローバル mise config 共有）で困難と判断したが、`~/.config/mise/conf.d/*.toml` が mise に自動ロードされることを実機検証し解決。linux.sh が Linux 時のみ `config/mise-linux.toml` を conf.d に配置（stow 対象外＝mac に存在しない）。全33 tool を `mise ls-remote` で解決確認。binary 名が repo 名と異なる 3 tool（rip2→rip / better-docker-ps→dops / tealdeer→tldr）は ubi の `exe=` で対応。実バイナリ install の最終確認のみ Linux での install.sh 実行時に持ち越し（aqua/ubi は platform-aware、`mise install -y || true` で fail-tolerant）
- **0-6**: `git worktree list --porcelain` の構造 parse に統一（旧 awk/sed は空白入りパス・detached HEAD で破綻）。`.wt-config` は override 方式（未配置時は従来デフォルト維持で挙動不変）
- **0-7**: `ralph-schedule` の `date -j`/`-d` は既に全て Darwin 分岐済みで移植性バグなし → 変更不要だった

## 書き換え候補（学習投資として）

ランク = (impact × learning) / effort × (1/blast-radius)

| Rank | 対象 | 現 → 新 | 根拠 | Effort |
|------|------|---------|------|--------|
| 1 | `tmux-{claude,codex,gemini,cursor}-usage.sh` + `cursor-auth-token.sh` を 1 binary へ | Bash → Rust | 学習（HTTP / OAuth refresh / file-lock / Keychain）+ 重複排除。non-load-bearing で最小 blast radius。`install.sh` への cargo-build 導線を試せる唯一の場所。container は `x86_64-unknown-linux-musl` / `cargo-zigbuild` で static 化。codex の atomic tmp+chmod+rename は保持 | M |
| 2 | `scripts/ralph-crew`（1182 行 daemon / worker / dispatch） | Bash → Go | 巨大 state machine の保守性 + 学習。daemon 専用ドメイン: goroutine が worker 並行に素直、`CGO_ENABLED=0` の container static が自明。XL・elective。Rank1 で compiled 導線が緑になってから着手。TUI screen-scrape の脆さは Go でも残る | XL |
| 3 | `scripts/wt` + `wt-lib.sh` | Bash → Rust | 学習（分岐の多い分類ロジックを enum/型で表現）+ testable classifier。Phase 0-6 の bash fix 済みが前提。CLI ドメインなので Rust | L |
| 4 | `scripts/ccusage-snapshot` | Bash+python3 hybrid → Babashka | データ処理層の学習台。JSON 集計 + date 処理を `bb` 一本に。Python の席を Babashka に明け渡す最初の実例。月 1 の cold job で低リスク | S |

`scripts/pomodoro.sh` は正直な学習候補だが event-driven で sketchybar に shell-out するだけ。意図した学習演習としてのみ着手、それまで bash 据え置き。

## LEAVE AS BASH（ponytail 規律 — ここが本体）

| 対象 | 一行理由 |
|------|---------|
| `statusline-command.sh`（hot path 本体） | 毎ターン描画の load-bearing binary は fresh box で fail-closed。sub-perceptual perf のために新 toolchain は不当 |
| `tmux-cpu/ram/gpu/storage.sh` | 3s キャッシュの zero-fork builtin `read` of /proc — binary で勝てない |
| `tmux-agent-*` / `tmux-claude-pane.sh` | tmux orchestration であって計算ではない。binary でも op ごとに tmux を fork。3s index daemon で既に最適解 |
| `regenerate-tmux-theme.sh` / `tmux-session-group.sh` | build-time config 生成 / fzf-driven glue。runtime コストなし |
| sketchybar plugins | macOS 限定 bar に cross-compile は不釣り合い。real fix は single-pass jq（bash） |
| `ralph-lib.sh` | undocumented・進化する `~/.claude.json` への surgical jq mutation。型 struct は json.RawMessage 地獄 = jq の劣化再実装 = net regression |
| `ralph-orchestrate` / `ralph-schedule` | crew との dead-or-alive を先に判定。OS glue（launchctl/plist/at）は irreducible shellout |
| ralph hooks（backpressure / session-context / precompact / stop-hook） | linter-dominated・fail-open な hook glue。hook path に versioned binary は負債のみ |
| `claude-status.sh` / `ai-notify.sh` / `claude-status-watch.sh` | hot path は ls+cat と jq -s 一発。実欠陥は Phase 0 の 1 語改名 + `jq -n`。XL 統合は over-engineering |
| `claude-gc` / `cs` / `claude-cleanup.sh` / `ccusage-schedule` / `env-context` | rm/git/tmux glue、fzf-native TUI、ps/awk、plist templating、eval-able shell 出力 — 他言語でも同じツールに shell-out |
| `install.sh` 本体 / `utils.sh` / container installer | pre-runtime bootstrap。bash が唯一保証された runtime。compiled rewrite は bootstrap コストを回収不能 |
| `migrate-claude-stow.sh` | run-once 移行で `install.sh` から呼ばれない。全機適用済みなら削除（git history が保持） |
| `just` / justfile 導入 | 却下。PATH 上に既にある script への alias に新 binary は shiny-tool。mise `[tasks]` か README 節で足りる |
| `dev-gateway` / `dev-tunnel` / `rcon-host-attach` / `cursor-auth-token.sh` | ssh dispatch / chroot pre-toolchain bootstrap / 300s-cached keychain ladder — compiled dep はむしろ有害 |
| `wt-traefik-up` | 機械生成 compose を awk parse。YAML 脆弱性は理論上。壊れたら awk→`yq` 一行、158 行 rewrite は不要 |
| nvim lua 全 51 file | embedded lua runtime。bash-shaped な部分が存在しない |
| `icon_map.sh`（1263 行） | 上流生成データ（sketchybar-app-font）。手で refactor せず version pin + install 時 pull |
| `clipboard-copy` / `git-find-big` / `gf` 等 | one-shot glue。compiled rewrite は制約された remote/popup 環境に bootstrap dep を追加する regression |
| pi extensions の `lib/` 抽出 | 「重複 exec wrapper」は inline stdlib execSync の誤認、「path builder」は file ごと別 subpath の 1 行 join。13 working file に未実証の cross-import 失敗モードを持ち込むだけ。endorse はするが抽出はしない |

## 言語戦略 — 5 層に固定、これ以上増やさない

このリポジトリの実態は glue が大半 + 少数の daemon/HTTP/CLI + agent 拡張 + データ処理スクリプト。authored code を次の 5 層に固定する。層が多いが、sprawl を防ぐのは「気分で選ばない、技術境界で選ぶ」という 1 点の縛り。各層は「どの問いに Yes か」で即答できる。

1. **Bash（デフォルト・glue 層、全体の 9 割）** — OS orchestration、hook、installer、tmux/launchctl/ssh plumbing。bootstrap 必須・hot-path・load-bearing は全部ここ
2. **TypeScript / Bun（agent 層・既存資産）** — pi extensions が既に TS。agent ロジック / 構造化データを扱う新規はここ
3. **Rust（compiled メイン層）** — 配布する native binary。CLI・HTTP client・usage widget・ユーザ向けツール全般。学習時間の大半をここに置く
4. **Go（並行 daemon 限定層）** — `ralph-crew` のような常駐 daemon / worker orchestration のみ。この 1 ドメインを超えて Go を広げない
5. **Babashka / Clojure（データ処理スクリプト層）** — Python が担っていた領域を置き換える。JSON/テキスト変換、jq/awk 重めのロジック付きスクリプト。単一 static binary の `bb` で走らせる。学習目的で採用

### 境界ルール（これを守れば 5 言語でも一貫する）

各層は次の問いで一意に決まる。コイン投げになった時点で破綻なので、即答できる状態を保つ:

- **bootstrap 必須 / hot-path / hook / installer か?** → Bash（何を足しても bare box で保証されるのは bash だけ）
- **agent ロジックか?** → TypeScript
- **配布する native binary か?（HTTP/OAuth/Keychain/性能/container 配布/ユーザ向けツール）** → Rust。starship(既に Rust)・fish・bat/eza/zoxide の主流で repo-consistent。cargo は mac.sh/linux.sh で bootstrap 済
- **常駐 daemon / worker 並行か?** → Go。goroutine + `CGO_ENABLED=0` container static。ralph-crew は rcon docker 内で走るためこの優位が効く
- **データ処理スクリプトか?（JSON/テキスト変換、ロジック付き glue、配布 binary は要らない）** → Babashka。従来 Python を選んでいた場所がここ

**Rust と Babashka の線引き（今回の主眼）**: 「配布する binary / ライブラリ(HTTP/Keychain)が要る」なら Rust、「その場で走らせるスクリプト / データを捏ねるだけ」なら Babashka。usage widget(HTTP/OAuth/Keychain) は Rust のまま、ccusage 系のデータ集計は Babashka。

**Python の扱い**: authored な Python プログラムは今後書かない（その席は Babashka）。ただし bash から `python3 -c`(tomllib 等) を CLI ツールとして呼ぶ既存箇所は「Python を書いている」わけではないので据え置き。

### コストの正直な明記

- install.sh に toolchain 3 つ（cargo = bootstrap 済、go = mise prebuilt、bb = 単一 static binary を mise/installer で取得）。build/取得 step が増える
- エコシステム 3 系統の保守、idiom 切り替え、学習の分散。5 層は上限で、これ以上は足さない
- Rust の container 配布は musl target / `cargo-zigbuild` でひと手間（Go の CGO_ENABLED=0 より重いが定石で解決可能）
- Babashka は Clojure/Lisp の学習コストを伴う（Python 既知の分の学習を Clojure に振り替える判断）

→ authored language は Bash / TypeScript / Rust / Go / Babashka の 5 つで打ち止め。MoonBit・Nix はこの 5 層に入れない（後述）。

## 実行順序（pilot → expand）

- **Phase 0**: bash quick wins（書き換えゼロ、実問題を全消し）— 完了（2026-07-18、7/7 push 済み）
- **Phase 1**: Rust 置換の完結 — `ai-usage`（usage 統合）+ `wt` + `pomodoro` を `tools/` workspace で実装（設計: [rust-cli-migration.md](rust-cli-migration.md) / [ai-usage-rust-pilot.md](ai-usage-rust-pilot.md)）。wt/pomodoro は当初 Phase 3 日和見だったが、Rust 面を一気に完結させる方針で前倒し
- **Phase 2 本命**: `ralph-crew` の Go 化（Phase 1 が緑になってから。daemon 専用ドメイン）
- **Phase 3 日和見**: `ccusage-snapshot`(Babashka, データ処理層の学習台)

## MoonBit・Nix の位置づけ（5 層に入れない）

- **MoonBit**: 言語設計と native 性能は本物だが pre-1.0 かつ ecosystem が薄い。dotfiles の compiled 層が要る HTTP/OAuth/Keychain/tmux 連携はまさにライブラリが要る領域で、薄い ecosystem と衝突する。mise にも無く bootstrap 未整備。→ dotfiles に入れず、得意な WASM/edge・外部依存ゼロの純計算 CLI を repo 外の独立サイドプロジェクトで学ぶ
- **Nix**: 全面 Nix 化は sudoなしメイン環境 + bare box 制約と正面衝突するため断念で正しい（Nix の再現性 vs「bash だけで再現」が衝突）。ただし flake の devshell (`nix develop`) を opt-in で採用する道はある。用途は compiled 層（Rust/Go binary）の 再現ビルド環境の pin に限定し、sudoなしメイン環境の dotfiles には一切触れない。sudoなし remote で nix 自体が要るなら nix-portable（静的・permissionless）が唯一堅実

## ハード制約

- `install.sh` 本体・`stow_*`・container installer・pre-toolchain bootstrap（`rcon-host-attach`）は bash 固定。bare remote box で保証される runtime は bash のみ
- 新規 compiled binary（Rust/Go）は必ず non-load-bearing から。statusline・hook・installer 本体という「fail するとセッションごと死ぬ経路」には永久に binary を置かない
- compiled 導入は「toolchain（cargo/mise-go）+ `install.sh` に build step、build 失敗時は当該 binary だけ欠ける degrade」の形に限定
- `just` は入れない

## 一言まとめ

Phase 0（bash 重複排除 + 既存バグ修正）で実利を取り切り、`*-usage.sh` の Rust 統合を学習パイロット、`ralph-crew`(Go, daemon 専用) を本命に据える。それ以外は全部 bash のまま。authored language は Bash / TypeScript / Rust / Go / Babashka の 5 つに固定（Rust=配布 binary、Go=常駐 daemon 限定、Babashka=Python が担っていたデータ処理スクリプト）、MoonBit・Nix は 5 層外、installer は永久に bash。

---

## Appendix: 業界 dotfiles の使用言語 統計（2025-2026）

この戦略の言語選択を裏付ける外部データ。

### dotfiles リポジトリの言語分布（GitHub `dotfiles` topic, 24,000+ repos）

| 言語 | repo 数 | 主用途 |
|------|--------|--------|
| Shell (bash/zsh) | 11,208 | shell 設定・install。圧倒的 1 位 |
| Lua | 3,494 | Neovim / wezterm / hammerspoon |
| Vim Script | 2,249 | 旧来 vim 設定 |
| Nix | 1,238 | home-manager / NixOS 宣言的管理 |
| Python | 1,037 | 管理ツール・生成スクリプト |
| Emacs Lisp | 697 | Emacs |
| CSS | 661 | GTK/rofi/waybar テーマ |
| JavaScript | 279 | - |
| PowerShell | 237 | Windows |
| TypeScript | 209 | 新興（設定生成・agent 系） |

### インタラクティブシェル分布（JetBrains Dev Ecosystem Survey 2025, カスタマイズ層）

Zsh 62% / Bash 31% / Fish 7%。Stack Overflow 2025 では開発者の 49% が bash/shell を使用。Oh My Zsh 170k+ stars。Fish 4.0（2025/02）で Rust に書き換え。

### dotfiles 管理ツールの実装言語

| ツール | 実装言語 | Stars | 備考 |
|--------|---------|-------|------|
| chezmoi | Go | ~20,600 | テンプレート/暗号化/クロスマシン。単一 static binary |
| Mackup | Python | ~15,300 | アプリ設定バックアップ寄り |
| Dotbot | Python | ~7,960 | YAML 定義ブートストラップ |
| yadm | Bash (git ラッパー) | ~6,350 | git 知識がそのまま使える |
| GNU Stow | Perl | 老舗 | symlink farm（本リポジトリ採用） |
| dotter | Rust | ~1,980 | テンプレート付き管理 |
| home-manager | Nix | - | 宣言的・再現性重視 |

パターン: 単純な symlink/git ラッパーは Shell/Perl、テンプレート・クロスプラットフォーム配布が要る本格ツールは Go(chezmoi) / Rust(dotter)、設定バックアップ層は Python。

### 実証研究（arXiv 2501.18555, 2025）

top 500 most-starred GitHub ユーザーの 25.8% が公開 dotfiles を保持。更新の 63.3% は設定調整、25.4% はプロジェクト meta 管理。最も追跡される設定は Vim と bash/zsh。

### 本リポジトリへの含意

本リポジトリ構成（Shell 主体 + Lua(nvim) + TS(pi 拡張)）は業界主流分布とほぼ一致。compiled 層の 2 言語分担も業界データが裏付ける: CLI/ツールは Rust が主流（starship/fish/bat/eza/zoxide）、常駐 daemon・管理ツールは Go が主流（chezmoi 20k stars）。「Rust=CLI / Go=daemon」の境界はこの分布とそのまま重なる。Nix は全面宣言的移行のもう一つの道だが、Stow 資産を捨てるコストが大きく現状は非推奨（devshell 限定で opt-in）。

### Sources

- https://github.com/topics/dotfiles
- https://github.com/twpayne/chezmoi
- https://dotfiles.github.io/utilities/
- https://arxiv.org/abs/2501.18555
- https://commandlinux.com/statistics/shell-usage-distribution-bash-vs-zsh-vs-fish-actual-usage-data/
- https://github.com/webpro/awesome-dotfiles
