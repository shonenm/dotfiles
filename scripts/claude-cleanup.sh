#!/bin/bash
# Claude Code プロセス管理スクリプト
# Usage: claude-cleanup.sh [list|kill|kill-all]

set -euo pipefail

# Claude CLIプロセスを検索（スクリプトやgrepを除外）
find_claude_processes() {
    ps aux | awk '$11 ~ /^claude$/' || true
}

# プロセス数をカウント
count_processes() {
    find_claude_processes | wc -l | tr -d ' '
}

# TTYからtmux pane情報を取得
get_tmux_pane_info() {
    local tty=$1
    if [[ "$tty" == "??" ]]; then
        echo "(detached)"
        return
    fi
    # tmuxのpane一覧からTTYでマッチ
    tmux list-panes -a -F '#{pane_tty}|#{session_name}:#{window_index}.#{pane_index}|#{pane_title}' 2>/dev/null | \
        grep "/dev/tty${tty}" | head -1 | cut -d'|' -f2,3 | tr '|' ' ' || echo "(not in tmux)"
}

# プロセス一覧を表示
list_processes() {
    local count
    count=$(count_processes)

    if [[ "$count" -eq 0 ]]; then
        echo "No Claude processes running."
        return 0
    fi

    echo "Found $count Claude process(es):"
    echo ""
    printf "%-7s %-6s %-6s %-12s %s\n" "PID" "CPU%" "MEM%" "PANE" "TITLE"
    echo "---------------------------------------------------------------"

    find_claude_processes | while read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        cpu=$(echo "$line" | awk '{print $3}')
        mem=$(echo "$line" | awk '{print $4}')
        tty=$(echo "$line" | awk '{print $7}')

        pane_info=$(get_tmux_pane_info "$tty")
        pane=$(echo "$pane_info" | awk '{print $1}')
        title=$(echo "$pane_info" | cut -d' ' -f2-)

        printf "%-7s %-6s %-6s %-12s %s\n" "$pid" "$cpu" "$mem" "$pane" "$title"
    done
}

# 指定PIDを終了
kill_process() {
    local pid=$1
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null
        sleep 0.5
        if kill -0 "$pid" 2>/dev/null; then
            echo "Failed to kill process $pid"
            return 1
        else
            echo "Killed process $pid"
        fi
    else
        echo "Process $pid not found"
    fi
}

# 全Claude プロセスを終了
kill_all() {
    local count
    count=$(count_processes)

    if [[ "$count" -eq 0 ]]; then
        echo "No Claude processes to kill."
        return 0
    fi

    echo "Killing $count Claude process(es)..."
    find_claude_processes | awk '{print $2}' | xargs kill -9 2>/dev/null || true
    sleep 0.5

    local remaining
    remaining=$(count_processes)
    if [[ "$remaining" -gt 0 ]]; then
        echo "Warning: $remaining process(es) still running"
    else
        echo "Done."
    fi
}

# メイン処理
case "${1:-list}" in
    list|ls)
        list_processes
        ;;
    kill)
        if [[ -n "${2:-}" ]]; then
            kill_process "$2"
        else
            echo "Usage: $0 kill <PID>"
            exit 1
        fi
        ;;
    kill-all|killall)
        kill_all
        ;;
    *)
        echo "Usage: $0 [list|kill <PID>|kill-all]"
        exit 1
        ;;
esac
