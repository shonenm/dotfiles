#!/bin/bash
# AI Agent ハング検知ウォッチャ
# running 状態のペーンの heartbeat 停滞を定期走査し、無応答を hang 表示する。
# tmux run-shell -b 経由で起動され、TMUX を継承する(claude-hooks.tmux)。
# 単一インスタンス保証(PID ロック、macOS/Linux 両対応で flock 非依存)。
# 仕様: docs/specs/agent-stop-notification.md

set -euo pipefail

[[ -z "${TMUX:-}" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL="${AGENT_HANG_INTERVAL:-15}"

LOCK_DIR="/tmp/claude"
LOCK_FILE="${LOCK_DIR}/hang-watch.pid"
mkdir -p "$LOCK_DIR"

# 既に生存インスタンスがあれば終了
if [[ -f "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
  exit 0
fi
echo $$ > "$LOCK_FILE"
# INT/TERM は cleanup 後に必ず exit する。exit しないと TERM を握り潰してループ継続し、
# pkill で死なず多重起動の原因になる。
cleanup() { rm -f "$LOCK_FILE"; }
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM

while true; do
  # tmux サーバが消えたら終了
  tmux info &>/dev/null || exit 0
  "$SCRIPT_DIR/tmux-claude-pane.sh" hang-scan 2>/dev/null || true
  # sleep を背景+wait にすることで INT/TERM を sleep 中でも即座に trap できる
  # (前景 sleep だと bash が trap を sleep 終了まで保留し、pkill が最大 INTERVAL 遅延する)
  sleep "$INTERVAL" & wait $! || true
done
