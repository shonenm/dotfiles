#!/bin/bash
# tmux Storage usage display (threshold-based)
# Only shows when root filesystem usage >= 80%
# Output: tmux-formatted string or empty if below threshold

THRESHOLD="${1:-80}"

# pill background (TokyoNight bg_highlight)
BG="#292e42"

# Nerd Font: disk icon (U+F0A0 - hdd)
DISK_ICON=$'\xef\x82\xa0'

# Parse disk usage percentage for root filesystem
disk_pct=$(df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}')

if [[ -n "$disk_pct" && "$disk_pct" =~ ^[0-9]+$ && $disk_pct -ge $THRESHOLD ]]; then
  if [[ $disk_pct -ge 95 ]]; then
    color="#f7768e"  # red - critical
  elif [[ $disk_pct -ge 90 ]]; then
    color="#e0af68"  # yellow - warning
  else
    color="#bb9af7"  # purple - notice
  fi
  printf '#[fg=#545c7e,bg=%s]|#[fg=#a9b1d6,bg=%s]%s #[fg=%s,bg=%s]%s%%' \
    "$BG" "$BG" "$DISK_ICON" "$color" "$BG" "$disk_pct"
fi
