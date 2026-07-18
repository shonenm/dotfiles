# Phase 2 設計 — ralph-crew の Go 化

`scripts/ralph-crew`（1182 行の bash daemon）を Go に置換する。
[language-refactor-strategy.md](language-refactor-strategy.md) の Phase 2、compiled 層の Go（常駐 daemon 限定ドメイン）。
唯一の正当化は 保守性 + Go 並行の学習。perf は根拠にしない（60s tick / jq コストは誤差）。

設計日: 2026-07-18

## M0 判定 — dead-or-alive（完了）

Phase 2 着手前に、隣接する ralph-orchestrate / ralph-schedule が crew に置換された legacy か調査した。結論: 両方 alive の別システム。crew に巻き込まない。

| システム | 実体 | skill | 役割 | Phase 2 での扱い |
|---------|------|-------|------|-----------------|
| crew | `ralph-crew`（daemon） | d-ralph-crew / d-crew-setup | 常駐し crew.json の schedule で task を定期注入する自律ワーカー | Go 化する（本 Phase） |
| orchestrate | `ralph-orchestrate` | d-ralph-parallel / collect / cleanup | タスクグラフから一発の並列ディスパッチ（手動起点） | bash 据え置き。別ツール |
| schedule | `ralph-schedule` + `ralph-schedule-exec.sh` | （launchd/at plist） | 指定時刻の one-shot 実行 | bash 据え置き。OS glue |

根拠:
- crew は `_start_worker`（内製）で worker を spawn し、ralph-orchestrate を呼ばない（自己完結）
- orchestrate は独自 skill 3 本を持つ現役ツール。crew と用途が違う（一発並列 vs 常駐 daemon）
- 従って「crew=orchestrate の後継だから orchestrate を消す/統合する」は誤り。3 者は独立

## 共有境界 — ralph-lib.sh は bash 据え置き

`ralph-lib.sh` は crew と orchestrate の両方が source する共有ライブラリ:
- `ralph_setup_worker_settings <cwd> <perms_json> <hook_json>`: worktree の `.claude/settings.local.json` を生成（Claude 所有スキーマへの jq 生成）
- `ralph_preaccept_trust <cwd>`: `~/.claude.json` の trust を surgical に jq mutation（監査が「型 struct 化は net regression」とした対象）

Go crew はこれを型付けせず shell-out する。ralph-lib.sh を dual-mode 化する:
- sourced（従来通り、orchestrate 用）: 関数を定義
- executed（新規、Go crew 用）: `ralph-lib setup-worker <args>` / `ralph-lib preaccept-trust <cwd>` の CLI dispatch を末尾に追加（`BASH_SOURCE == $0` ガード）

これで jq mutation は bash に温存し、Go は薄い shell-out 境界だけ持つ。

## スコープ境界

IN（Go 化）: ralph-crew の daemon loop / worker lifecycle / dispatch / status / cleanup / send / restart / teardown

OUT（bash 据え置き）:
- `ralph-lib.sh`（jq mutation。dual-mode 化のみ）
- `ralph-orchestrate` / `ralph-schedule`（別システム、M0 で確定）
- ralph hooks（Claude Code の fail-open hook glue）
- claude TUI 本体（screen-scrape 対象、Go でも脆さは変わらない）
- worktree 操作 → Phase 1 の `wt` binary に shell-out

## アーキテクチャ（Go）

```
tools/crew/
  main.go            subcommand dispatch (init/dispatch/daemon/status/send/restart/cleanup/teardown)
  config.go          crew.json パース。workers[].permissions は Claude 所有の進化スキーマなので
                     json.RawMessage で保持（型付けしない = ralph-lib の教訓）
  daemon.go          singleton(pidfile) + tick loop + signal(context cancel) + supervisor
  worker.go          spawn(wt→tmux→claude→/ralph 送信) / status(capture-pane parse)
  dispatch.go        schedule 評価 (interval/standing/once) + should_dispatch/should_restart
  tmux.go            tmux ラッパー (os/exec)
  gitx.go            git + wt binary shell-out
  ralphlib.go        ralph-lib.sh への shell-out (setup-worker / preaccept-trust)
```

依存方針: 標準ライブラリ優先。JSON は encoding/json、CLI は std flag（cobra は必要になったら）。
外部 crate/module は原則入れない。

## 学習うまみ vs Go でも改善しない部分（正直に）

濃い（Go の核心）:
- goroutine + channel による worker 並行監視 supervisor（bash の逐次 tick を並行化）
- context/signal による graceful shutdown
- daemon singleton lifecycle、schedule state machine
- json.RawMessage による partial-parse（所有者が別スキーマの一部だけ触る設計）

改善しない（過大評価しない）:
- claude TUI の capture-pane screen-scrape（Go でも grep ベースで脆い）
- tmux orchestration は op ごとに tmux を fork するのは不変
- perf は根拠にならない

## マイルストーン

| M | 内容 | ゲート | 状態 |
|---|------|--------|------|
| M0 | orchestrate/schedule の dead-or-alive 判定 | alive 確定 → 別システムとして据え置き | 完了 |
| M1 | Go module + crew.json パース（struct + RawMessage） | 実 crew.json 往復 + unit test | 完了 |
| M2 | `status`（read-only、最も安全） | bash 版と table/--json 一致 | 完了 |
| M3 | daemon skeleton（singleton + tick + signal graceful stop） | 起動/停止/多重起動防止 E2E | 完了 |
| M4 | worker spawn + dispatch（ralph-lib dual-mode 化含む） | prompt/worker.json byte-parity + 隔離 tmux で init→dispatch E2E | 完了 |
| M5 | cleanup/send/restart/teardown + install 導線（go build） | 全 subcommand smoke + crew を ~/.local/bin へ並走配置 | 完了 |
| M6 | cutover 準備（並走配置、検証手順） | bash ralph-crew は据え置き、実サイクル実証後に cutover | 完了 |

## 実装完了 (2026-07-18) — 並走フェーズ

Go crew (`tools/crew`) を実装し、`install_compiled_tools` が `~/.local/bin/crew` に配置。
bash `scripts/ralph-crew` は据え置きで並走（binary 名が別 = crew vs ralph-crew）。

検証済み（session 内で可能な範囲）:
- config パース / status（table・--json）: bash と byte-parity
- prompt テンプレート（none/issue-only）・worker.json: bash heredoc / jq -n と byte-identical
- daemon: pidfile singleton・多重起動拒否・SIGTERM graceful stop を実バイナリ E2E
- init→worker spawn→dispatch→send/restart/cleanup/teardown: 隔離 tmux socket + fake claude で full path E2E
- ralph-lib.sh dual-mode: sourced（orchestrate 互換）+ CLI（Go shell-out）両対応、権限調整 jq 一致

未検証（並走フェーズで実証する）:
- 実 claude を worker として多時間の自律サイクルを回せるか（screen-scrape の idle 判定、
  respawn による fresh context、rate limit 自動確認が実 TUI で機能するか）

### 並走検証の手順

実プロジェクトで bash と Go を切り替えて比較:

```bash
# bash 版 (現行)
ralph-crew daemon --config .claude/crew.json
# Go 版 (検証)
crew daemon --config .claude/crew.json
```

`crew status` / `crew status --json` は副作用が最小なので、bash daemon 稼働中に
Go の status を並べて出力一致を確認するのが最も安全な第一歩。

### cutover 基準（満たしたら bash を削除）

1. 実プロジェクトで `crew daemon` が worker を spawn し、1 サイクル以上 task を dispatch → PR まで自律で回る
2. idle 判定 / restart / rate limit 自動確認が実 TUI で bash と同等に機能
3. mac + Linux(ailab) 両方で確認

満たした時点で: bash `scripts/ralph-crew` 削除、d-crew-setup / d-ralph-crew skill と
docs の `ralph-crew` 参照を `crew` に更新。それまでは並走。

## リスク・cutover 方針

- Phase 中最大の blast radius。crew は ailab で実運用中（daemon 常駐）で load-bearing
- usage widget と違い「多時間の自律サイクルを回せる」ことが parity の定義。session 内で完全 E2E は不可
- 従って M6 は「Go binary を並走配置 + install 導線」までとし、bash `ralph-crew` は即削除しない。実プロジェクトで Go daemon が1サイクル自律で回せたと実証してから旧 bash を削除する（Phase 1 の usage widget より並走期間を長く取る）
- screen-scrape の脆さは移行では解決しない（別課題として明示）
- install は `install_rust_tools` → `install_compiled_tools`（cargo + mise-go）にリネーム
