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

# Nerd Font: memory icon (U+EFF5)
RAM_ICON=$'\xee\xbf\xb5'

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

ram_pct=""

case "$(uname -s)" in
  Linux)
    # /proc/meminfo: MemTotal and MemAvailable (kernel 3.14+)
    while IFS=': ' read -r key val _; do
      case "$key" in
        MemTotal) mem_total=$val ;;
        MemAvailable) mem_avail=$val ;;
      esac
    done < /proc/meminfo
    if [[ -n "$mem_total" && -n "$mem_avail" && "$mem_total" -gt 0 ]]; then
      ram_pct=$(( (mem_total - mem_avail) * 100 / mem_total ))
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
  if [[ $ram_pct -ge 90 ]]; then
    color="#f7768e"  # red - high
  elif [[ $ram_pct -ge 70 ]]; then
    color="#e0af68"  # yellow - medium
  else
    color="#9ece6a"  # green - low
  fi
  result="#[fg=#a9b1d6,bg=$BG]$RAM_ICON #[fg=$color,bg=$BG]$(printf '%2d%%' "$ram_pct")"
else
  result="#[fg=#a9b1d6,bg=$BG]$RAM_ICON #[fg=#545c7e,bg=$BG]--"
fi

printf '%s' "$result" > "$CACHE_FILE"
printf '%s' "$result"
