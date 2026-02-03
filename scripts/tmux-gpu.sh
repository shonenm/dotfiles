#!/bin/bash
# tmux GPU usage display (cross-platform)
# macOS: macmon (Apple Silicon, no sudo)
# Linux: nvidia-smi (NVIDIA GPU)
# Output: tmux-formatted string or empty if unavailable

CACHE_DIR="/tmp/tmux_sysstat"
CACHE_FILE="$CACHE_DIR/gpu"
CACHE_TTL=3  # seconds

# pill background (TokyoNight bg_highlight)
BG="#292e42"

# Nerd Font: GPU icon (U+F26C - display)
GPU_ICON=$'\xef\x89\xac'

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

gpu_pct=""

case "$(uname -s)" in
  Darwin)
    if command -v macmon &>/dev/null; then
      json=$(timeout 2 macmon pipe -s 1 -i 100 2>/dev/null | head -1)
      if [[ -n "$json" ]]; then
        gpu_pct=$(echo "$json" | jq -r '.gpu_usage[1] // empty' 2>/dev/null)
        [[ -n "$gpu_pct" ]] && gpu_pct=$(printf "%.0f" "$gpu_pct")
      fi
    fi
    ;;
  Linux)
    if command -v nvidia-smi &>/dev/null; then
      gpu_pct=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    fi
    ;;
esac

if [[ -n "$gpu_pct" && "$gpu_pct" =~ ^[0-9]+$ ]]; then
  if [[ $gpu_pct -ge 80 ]]; then
    color="#f7768e"  # red - high
  elif [[ $gpu_pct -ge 50 ]]; then
    color="#e0af68"  # yellow - medium
  else
    color="#9ece6a"  # green - low
  fi
  result="#[fg=#545c7e,bg=$BG]|#[fg=#a9b1d6,bg=$BG]$GPU_ICON #[fg=$color,bg=$BG]${gpu_pct}%"
  printf '%s' "$result" > "$CACHE_FILE"
  printf '%s' "$result"
else
  # No GPU data - output nothing, cache empty result
  : > "$CACHE_FILE"
fi
