#!/bin/bash
# tmux CPU usage display (cross-platform)
# Linux: /proc/stat delta calculation (no external dependencies)
# macOS: iostat (standard, same as tmux-cpu plugin)
# Output: tmux-formatted string with icon and colored percentage

CACHE_DIR="/tmp/tmux_sysstat"
CACHE_FILE="$CACHE_DIR/cpu"
CACHE_TTL=3  # seconds
STATE_FILE="$CACHE_DIR/cpu_stat"  # previous /proc/stat snapshot for delta

# pill background (TokyoNight bg_highlight)
BG="#292e42"

# Nerd Font: microchip icon (U+F2DB)
CPU_ICON=$'\xef\x8b\x9b'

mkdir -p "$CACHE_DIR"

source "${BASH_SOURCE%/*}/tmux-utils.sh"

# Check cache freshness
if [[ -f "$CACHE_FILE" ]]; then
  now=$(date +%s)
  mtime=$(get_mtime "$CACHE_FILE")
  cache_age=$(( now - mtime ))
  if [[ $cache_age -lt $CACHE_TTL ]]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

cpu_pct=""

case "$(uname -s)" in
  Linux)
    # Read current /proc/stat (first line: cpu  user nice system idle iowait irq softirq steal)
    read -r _ cur_user cur_nice cur_system cur_idle cur_iowait cur_irq cur_softirq cur_steal _ < /proc/stat
    cur_total=$(( cur_user + cur_nice + cur_system + cur_idle + cur_iowait + cur_irq + cur_softirq + cur_steal ))
    cur_idle_all=$(( cur_idle + cur_iowait ))

    if [[ -f "$STATE_FILE" ]]; then
      read -r prev_total prev_idle_all < "$STATE_FILE"
      diff_total=$(( cur_total - prev_total ))
      diff_idle=$(( cur_idle_all - prev_idle_all ))
      if [[ $diff_total -gt 0 ]]; then
        cpu_pct=$(( (diff_total - diff_idle) * 100 / diff_total ))
      fi
    fi

    # Save current state for next delta
    echo "$cur_total $cur_idle_all" > "$STATE_FILE"
    ;;
  Darwin)
    # iostat: run 2 samples, take the last line (first is since-boot average)
    raw=$(iostat -c 2 disk0 2>/dev/null | tail -1)
    if [[ -n "$raw" ]]; then
      # iostat columns: disk(KB/t tps MB/s) cpu(us sy id) load(1m 5m 15m)
      idle=$(echo "$raw" | awk '{print $6}')
      if [[ -n "$idle" && "$idle" =~ ^[0-9]+$ ]]; then
        cpu_pct=$(( 100 - idle ))
      fi
    fi
    ;;
esac

if [[ -n "$cpu_pct" && "$cpu_pct" =~ ^[0-9]+$ ]]; then
  if [[ $cpu_pct -ge 80 ]]; then
    color="#f7768e"  # red - high
  elif [[ $cpu_pct -ge 50 ]]; then
    color="#e0af68"  # yellow - medium
  else
    color="#9ece6a"  # green - low
  fi
  result="#[fg=#a9b1d6,bg=$BG]$CPU_ICON #[fg=$color,bg=$BG]$(printf '%2d%%' "$cpu_pct")"
else
  # First run (no delta yet) or error - show placeholder
  result="#[fg=#a9b1d6,bg=$BG]$CPU_ICON #[fg=#545c7e,bg=$BG]--"
fi

printf '%s' "$result" > "$CACHE_FILE"
printf '%s' "$result"
