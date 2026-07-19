#!/bin/bash
# AI Agent ハング検知ウォッチャ
# running 状態のペーンの heartbeat 停滞を定期走査し、無応答を hang 表示する。
# tmux run-shell -b 経由で起動され、TMUX を継承する(claude-hooks.tmux)。
# 単一インスタンス保証(PID ロック、macOS/Linux 両対応で flock 非依存)。
# 仕様: docs/specs/agent-stop-notification.md

set -euo pipefail

[[ -z "${TMUX:-}" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/tmux-agent-lib.sh"
INTERVAL="${AGENT_HANG_INTERVAL:-15}"

LOCK_DIR="$(agent_runtime_dir)"
LOCK_FILE="${LOCK_DIR}/hang-watch.pid"
mkdir -p "$LOCK_DIR"

# 既に同じwatcherが生存していれば終了。PID再利用された無関係processはlock所有者とみなさない。
if [[ -f "$LOCK_FILE" ]]; then
  existing=$(cat "$LOCK_FILE" 2>/dev/null || true)
  command=$(ps -p "$existing" -o command= 2>/dev/null || true)
  [[ -n "$existing" && "$command" == *tmux-agent-hang-watch.sh* ]] && exit 0
fi
echo $$ > "$LOCK_FILE"
# INT/TERM は cleanup 後に必ず exit する。exit しないと TERM を握り潰してループ継続し、
# pkill で死なず多重起動の原因になる。
# cleanup は自分が所有する lock のみ削除する。別インスタンスが lock を奪った後に自分が
# exit するとき、無条件 rm だと勝者の lock を消してしまうため。
cleanup() { [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]] && rm -f "$LOCK_FILE"; }
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM

while true; do
  # tmux サーバが消えたら終了
  tmux info &>/dev/null || exit 0
  # 起動時ロックすり抜け (旧インスタンス生存中に lock が消えて新規が起動) で多重化した場合、
  # lock を新インスタンスに奪われた旧インスタンスはここで畳む → 単一インスタンスへ収束。
  owner="$(cat "$LOCK_FILE" 2>/dev/null || true)"
  [[ -n "$owner" && "$owner" != "$$" ]] && exit 0
  "$SCRIPT_DIR/tmux-claude-pane.sh" hang-scan 2>/dev/null || true
  # sleep を背景+wait にすることで INT/TERM を sleep 中でも即座に trap できる
  # (前景 sleep だと bash が trap を sleep 終了まで保留し、pkill が最大 INTERVAL 遅延する)
  sleep "$INTERVAL" & wait $! || true
done
