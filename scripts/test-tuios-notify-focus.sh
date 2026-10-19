#!/bin/bash
# TUIOS内のAI通知: 位置の記録、focus hookでの消去、SketchyBarでの判定を確認する。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tuios-notify-test.XXXXXX")"
STATUS_DIR="$TMP/shared/claude/status"
BIN="$TMP/bin"
TIMER_STATE=""

cleanup() {
  local pid
  for state in "$TMP"/runtime/claude/*/focus "$TMP/runtime/sketchybar/workspace_focus"; do
    [[ -f "$state" ]] || continue
    for pid in $(tr ':' '\n' < "$state" | grep -E '^[0-9]{3,}$' || true); do
      kill "$pid" 2>/dev/null || true
    done
  done
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'echo "FAIL: line $LINENO: $BASH_COMMAND" >&2' ERR

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'${3:+ ($3)}"; }

mkdir -p "$BIN" "$STATUS_DIR" "$TMP/runtime" "$TMP/home/.local/share/claude" "$TMP/data/ai-notify"
# 外部コマンドは記録だけするstubに置き換える。
cat > "$BIN/sketchybar" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
EOF
cat > "$BIN/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF
cat > "$BIN/aerospace" <<'EOF'
#!/bin/bash
case "$*" in
  "list-workspaces --focused") echo 3 ;;
  "list-windows --focused --json") echo '[{"app-name":"Ghostty"}]' ;;
  *) echo 3 ;;
esac
EOF
cat > "$BIN/tuios" <<'EOF'
#!/bin/bash
case "$1" in
  list-clients) echo '[{"client_id":"c","pid":1,"session":"work"},{"client_id":"d","pid":1,"session":""}]' ;;
  list-windows) echo "{\"focused_window_id\":\"$STUB_FOCUSED\"}" ;;
esac
EOF
chmod +x "$BIN"/*
export PATH="$BIN:$PATH" STUB_LOG="$TMP/stub.log" DOTFILES_SHARED_DIR="$TMP/shared" XDG_RUNTIME_DIR="$TMP/runtime"
unset TMUX

notify() {
  local session="$1" pane="$2" id="$3"
  jq -n --arg s "$session" --arg w "$pane" --argjson u "$(date +%s)" \
    '{status:"idle", project:"p", workspace:"3", tmux_session:$s, tmux_window_index:$w, updated:$u}' \
    > "$STATUS_DIR/workspace_3_${id}.json"
}

# 1. ai-notify は TUIOS pane の位置を tuios:<session> / pane ID で記録する。
echo "{\"$TMP/repo\":{\"workspace\":\"3\"}}" > "$TMP/home/.local/share/claude/workspace_map.json"
git init -q "$TMP/repo"
: > "$TMP/data/ai-notify/claude_webhook"  # 空webhook: Slack送信をしない
echo "{\"cwd\":\"$TMP/repo\"}" | HOME="$TMP/home" XDG_DATA_HOME="$TMP/data" \
  TUIOS_SESSION=work TUIOS_PANE_ID=pane-a "$ROOT/scripts/ai-notify.sh" claude idle
for _ in {1..100}; do
  compgen -G "$STATUS_DIR/workspace_3_*.json" >/dev/null && break
  sleep 0.05
done
file=$(compgen -G "$STATUS_DIR/workspace_3_*.json" | head -1)
[[ -n "$file" ]] || fail "ai-notify did not write a status file"
assert_eq "$(jq -r '.tmux_session' "$file")" "tuios:work" "recorded session"
assert_eq "$(jq -r '.tmux_window_index' "$file")" "pane-a" "recorded pane"
rm -f "$STATUS_DIR"/*.json

# 2. after-focus-change: 5秒以上見た前の pane の通知だけを消し、別 pane の通知は残す。
notify tuios:work pane-a 1
notify tuios:work pane-b 2
notify tuios:other pane-a 3
focus_hook() {
  TUIOS_EVENT=after-focus-change TUIOS_SESSION_ID="$1" TUIOS_WINDOW_ID="$2" "$ROOT/scripts/tmux-claude-focus.sh"
}
focus_hook work pane-a
TIMER_STATE=$(compgen -G "$TMP/runtime/claude/*/focus" | head -1)
[[ -n "$TIMER_STATE" ]] || fail "focus state was not recorded"
state=$(cat "$TIMER_STATE")
assert_eq "${state%:*:*}" "tuios:work:pane-a" "focus state position"
# 滞在時間を5秒以上前にずらしてから pane-b へ移る。
pid="${state##*:}"; rest="${state%:*}"; ts="${rest##*:}"
echo "tuios:work:pane-a:$((ts - 10)):$pid" > "$TIMER_STATE"
focus_hook work pane-b
remaining=$(jq -r '"\(.tmux_session) \(.tmux_window_index)"' "$STATUS_DIR"/*.json | sort | tr '\n' ',')
assert_eq "$remaining" "tuios:other pane-a,tuios:work pane-b," "focus clears only the left pane"

# 3. SketchyBar: focus 中の TUIOS pane の通知だけを「表示中」とみなす。
rm -f "$STATUS_DIR"/*.json
notify tuios:work pane-a 1
notify tuios:work pane-b 2
run_plugin() {
  : > "$STUB_LOG"
  mkdir -p "$TMP/sbconfig/plugins"
  : > "$TMP/sbconfig/plugins/colors.sh"
  CONFIG_DIR="$TMP/sbconfig" SENDER="$1" NAME=claude STUB_FOCUSED="$2" \
    bash "$ROOT/common/sketchybar/.config/sketchybar/plugins/claude.sh"
}
# pane-b を見ている: pane-a の通知が別 pane にあるため消去タイマーを始めない。
run_plugin claude_status_change pane-b
[[ ! -f "$TMP/runtime/sketchybar/workspace_focus" ]] || fail "timer started while another pane has a notification"

# focus 変更で5秒後に、表示中の pane-b だけを消す。
run_plugin front_app_switched pane-b
sleep 6
remaining=$(jq -r '.tmux_window_index' "$STATUS_DIR"/*.json | tr '\n' ',')
assert_eq "$remaining" "pane-a," "sketchybar timer clears only the pane on screen"

echo "OK: tuios notify focus"
