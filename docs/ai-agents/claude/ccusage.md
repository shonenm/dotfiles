# ccusage

`ccusage` は各 AI コーディング CLI がローカルに保存する利用記録を集計するツール。Claude Code、Codex、pi、Gemini などを日別・週別・月別に確認できる。請求額ではなくローカル記録と価格表に基づく**推定値**として扱う。

## 導入

`config/packages.npm.txt` で `ccusage@20.0.17` を固定している。通常は `install.sh` を再実行する。導入確認:

```bash
ccusage --version
# 20.x を確認
```

`~/.claude/ccusage.json` は Stow 管理され、日付境界を `Asia/Tokyo`、価格取得を offline に固定する。更新時は npm 最新版を確認し、`config/packages.npm.txt` のバージョンを更新してから `scripts/test-ccusage-snapshot.sh` を実行する。

## 日常の確認

```bash
ccusage daily --all
ccusage weekly --all --breakdown
ccusage monthly --all --breakdown
ccusage claude daily --instances
ccusage blocks
```

- `--all`: 検出した agent の統合集計
- `--instances`: Claude Code のプロジェクト別集計。プロジェクト名を含むため共有しない
- `blocks`: Claude Code の5時間 block の利用傾向。tmux の現在クォータ表示とは別の履歴分析

既存の `tmux-claude-usage.sh` は OAuth API の現在の5時間/週クォータを表示する。ccusage は履歴統計なので置換しない。

## 月次証跡

```bash
ccusage-snapshot          # 前月
ccusage-snapshot 2026-06 # 指定月
```

出力先は `${XDG_STATE_HOME:-~/.local/state}/ccusage/snapshots/YYYY/MM/`。

| ファイル | 内容 |
| --- | --- |
| `all-daily.json` | 全 agent の日別集計 |
| `claude-projects.json` | Claude Code のプロジェクト別日次集計 |
| `manifest.json` | 期間、timezone、ccusage版、設定・レポートの SHA-256 |

snapshot は既存月を上書きしない。`cs --clean` などで原本 JSONL を消す前に作成する。原本 (`~/.claude/projects/`、`~/.pi/agent/sessions/` 等) と snapshot 内のプロジェクト名は Git、dotfiles、スクリーンショット、非暗号化クラウド同期へ入れない。

## 月次スケジュール

スケジュールは opt-in。毎月1日 00:10 に前月の未作成 snapshot を保存する。

```bash
ccusage-schedule enable
ccusage-schedule status
ccusage-schedule disable
```

- macOS: user LaunchAgent (`com.user.ccusage-snapshot`)
- Linux: user systemd timer (`ccusage-snapshot.timer`, `Persistent=true`)
- ログ: `${XDG_STATE_HOME:-~/.local/state}/ccusage/log/`

`enable` は実行中の dotfiles checkout を参照するジョブを作成する。dotfiles のパスを移動したら一度 `disable` してから `enable` し直す。

## 検証

```bash
scripts/test-ccusage-snapshot.sh
shellcheck scripts/ccusage-snapshot scripts/ccusage-schedule scripts/test-ccusage-snapshot.sh
```

テストは fake ccusage を使い、実際の会話ログを読み込まない。
