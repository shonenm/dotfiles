#!/usr/bin/env bash
# Claude Code statusLine command
# Mirrors starship prompt elements: directory | git branch | model | context | time

input=$(cat)
echo "$input" > /tmp/statusline-input.json

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')

# Directory: shorten to last 2 components (mirrors starship truncation_length=2)
if [ -n "$cwd" ]; then
  home_replaced="${cwd/#$HOME/~}"
  dir=$(echo "$home_replaced" | awk -F'/' '{
    n=NF;
    if (n <= 2) { print $0 }
    else { print $(n-1) "/" $n }
  }')
else
  dir="?"
fi

# Git branch (skip lock to avoid blocking)
git_branch=""
if [ -n "$cwd" ] && [ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git -C "$cwd" -c gc.auto=0 branch --show-current 2>/dev/null)
fi

# Context bar (10 chars wide)
ctx_bar=""
if [ -n "$used_pct" ]; then
  used_int=$(printf "%.0f" "$used_pct")
  filled=$(( used_int / 10 ))
  empty=$(( 10 - filled ))
  bar=""
  for _ in $(seq 1 "$filled"); do bar="${bar}█"; done
  for _ in $(seq 1 "$empty");  do bar="${bar}░"; done
  ctx_bar="${bar} ${used_int}%"
fi

# ANSI colors (Dracula palette)
PINK='\033[38;2;255;121;198m'
GREEN='\033[38;2;80;250;123m'
CYAN='\033[38;2;139;233;253m'
PURPLE='\033[38;2;189;147;249m'
YELLOW='\033[38;2;241;250;140m'
DIM='\033[2m'
RESET='\033[0m'

sep=" ${DIM}|${RESET} "

# Line 1: dir [branch] [vim]
line1="${PINK}${dir}${RESET}"
if [ -n "$git_branch" ]; then
  line1="${line1}${sep}${GREEN}${git_branch}${RESET}"
fi
if [ -n "$vim_mode" ]; then
  line1="${line1}${sep}${YELLOW}${vim_mode}${RESET}"
fi

# Line 2: model | ctx | time
line2_parts=()
if [ -n "$model" ]; then
  line2_parts+=("${CYAN}${model}${RESET}")
fi
if [ -n "$ctx_bar" ]; then
  line2_parts+=("${PURPLE}ctx:${ctx_bar}${RESET}")
fi
time_str=$(date +%H:%M)
line2_parts+=("${DIM}${time_str}${RESET}")

line2=""
for part in "${line2_parts[@]}"; do
  if [ -z "$line2" ]; then
    line2="$part"
  else
    line2="${line2}${sep}${part}"
  fi
done

printf "%b\n%b\n" "$line1" "$line2"
