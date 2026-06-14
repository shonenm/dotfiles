#!/bin/bash
# tmux RAM usage display (cross-platform)
# Linux: /proc/meminfo (no external dependencies)
# macOS: vm_stat (standard, same as tmux-cpu plugin)
# Output: tmux-formatted string with icon and colored percentage

CACHE_DIR="/tmp/tmux_sysstat"
CACHE_FILE="$CACHE_DIR/ram"
CACHE_TTL=3  # seconds

# pill background (TokyoNight bg_highlight)
BG="#292e42"

# Nerd Font: memory icon (nf-md-memory, U+F035B)
RAM_ICON=$'\xf3\xb0\x8d\x9b'

mkdir -p "$CACHE_DIR"

# shellcheck source=/dev/null
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

ram_pct=""
swap_pct=""  # used swap as percent of total; "" when unknown (e.g. macOS)

case "$(uname -s)" in
  Linux)
    # /proc/meminfo: MemTotal/MemAvailable (kernel 3.14+) and swap
    while IFS=': ' read -r key val _; do
      case "$key" in
        MemTotal) mem_total=$val ;;
        MemAvailable) mem_avail=$val ;;
        SwapTotal) swap_total=$val ;;
        SwapFree) swap_free=$val ;;
      esac
    done < /proc/meminfo
    if [[ -n "$mem_total" && -n "$mem_avail" && "$mem_total" -gt 0 ]]; then
      ram_pct=$(( (mem_total - mem_avail) * 100 / mem_total ))
    fi
    if [[ -n "${swap_total:-}" && "$swap_total" -gt 0 && -n "${swap_free:-}" ]]; then
      swap_pct=$(( (swap_total - swap_free) * 100 / swap_total ))
    fi
    ;;
  Darwin)
    # vm_stat: page size and page counts
    page_size=$(vm_stat 2>/dev/null | head -1 | grep -o '[0-9]*')
    if [[ -n "$page_size" ]]; then
      # Parse relevant page counts
      eval "$(vm_stat 2>/dev/null | awk -F: '/Pages (free|active|inactive|speculative|wired down|occupied by compressor)/ {
        gsub(/[^0-9]/, "", $2);
        gsub(/[^a-zA-Z]/, "_", $1);
        print $1 "=" $2
      }')"
      # Total physical memory via sysctl
      total_bytes=$(sysctl -n hw.memsize 2>/dev/null)
      if [[ -n "$total_bytes" && -n "$Pages_free" ]]; then
        # Used = total - (free + inactive + speculative) * page_size
        free_pages=$(( ${Pages_free:-0} + ${Pages_inactive:-0} + ${Pages_speculative:-0} ))
        free_bytes=$(( free_pages * page_size ))
        used_bytes=$(( total_bytes - free_bytes ))
        if [[ $total_bytes -gt 0 ]]; then
          ram_pct=$(( used_bytes * 100 / total_bytes ))
        fi
      fi
    fi
    ;;
esac

if [[ -n "$ram_pct" && "$ram_pct" =~ ^[0-9]+$ ]]; then
  swap_pct=${swap_pct:-0}
  # Critical when RAM is nearly full OR swap is under real pressure. The swap
  # term matters: a thrashing host can sit at ~88% RAM (sub-90) while swap is
  # exhausted -- RAM% alone would stay yellow and hide the problem.
  critical=0
  if [[ $ram_pct -ge 90 || $swap_pct -ge 50 ]]; then
    color="#f7768e"; critical=1  # red - critical
  elif [[ $ram_pct -ge 70 ]]; then
    color="#e0af68"              # yellow - medium
  else
    color="#9ece6a"              # green - low
  fi
  result="#[fg=#a9b1d6,bg=$BG]$RAM_ICON #[fg=$color,bg=$BG]$(printf '%2d%%' "$ram_pct")"
  if [[ $critical -eq 1 ]]; then
    # Surface what to act on: show swap when it is the trigger, and name the
    # single largest RSS process. ps/sort run only on this rare critical path.
    extra=""
    [[ $swap_pct -ge 50 ]] && extra="sw$(printf '%d%%' "$swap_pct") "
    read -r top_kb top_comm < <(ps axo rss=,comm= 2>/dev/null | sort -rn | head -1)
    if [[ -n "${top_kb:-}" && "$top_kb" =~ ^[0-9]+$ ]]; then
      extra="${extra}${top_comm##*/} $(( top_kb / 1048576 )).$(( (top_kb % 1048576) * 10 / 1048576 ))G"
    fi
    [[ -n "$extra" ]] && result="$result #[fg=#545c7e,bg=$BG]$extra"
  fi
else
  result="#[fg=#a9b1d6,bg=$BG]$RAM_ICON #[fg=#545c7e,bg=$BG]--"
fi

printf '%s' "$result" > "$CACHE_FILE"
printf '%s' "$result"
