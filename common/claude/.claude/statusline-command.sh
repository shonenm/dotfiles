#!/usr/bin/env bash
# Claude Code statusLine command — Dracula palette, 3-line layout

input=$(cat)
echo "$input" > /tmp/statusline-input.json

# --- Extract fields ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
worktree=$(echo "$input" | jq -r '.worktree.name // .workspace.git_worktree // empty')
agent=$(echo "$input" | jq -r '.agent.name // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')
rate5h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rate5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

# --- Directory: last 2 components ---
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

# --- Git branch ---
git_branch=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git -C "$cwd" -c gc.auto=0 branch --show-current 2>/dev/null)
fi

# --- Context bar (10 chars) ---
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

# --- Cost ---
cost_str=""
if [ -n "$cost" ] && [ "$cost" != "0" ]; then
  cost_str=$(printf '$%.4f' "$cost")
fi

# --- Duration ---
duration_str=""
if [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ]; then
  secs=$(( ${duration_ms%.*} / 1000 ))
  if [ "$secs" -ge 3600 ]; then
    duration_str=$(printf '%dh%02dm' $(( secs / 3600 )) $(( (secs % 3600) / 60 )))
  else
    duration_str=$(printf '%dm%02ds' $(( secs / 60 )) $(( secs % 60 )))
  fi
fi

# --- Lines changed ---
lines_str=""
if [ -n "$lines_added" ] && [ -n "$lines_removed" ]; then
  if [ "$lines_added" != "0" ] || [ "$lines_removed" != "0" ]; then
    lines_str="+${lines_added} -${lines_removed}"
  fi
fi

# --- Rate limit 5h ---
rate_str=""
if [ -n "$rate5h_pct" ]; then
  rate_int=$(printf "%.0f" "$rate5h_pct")
  if [ -n "$rate5h_reset" ] && [ "$rate5h_reset" != "null" ]; then
    now=$(date +%s)
    remaining_secs=$(( rate5h_reset - now ))
    if [ "$remaining_secs" -gt 0 ]; then
      rm=$(( remaining_secs / 60 ))
      rate_str="5h:${rate_int}% (rst ${rm}m)"
    else
      rate_str="5h:${rate_int}%"
    fi
  else
    rate_str="5h:${rate_int}%"
  fi
fi

# --- Colors (Dracula) ---
PINK='\033[38;2;255;121;198m'
GREEN='\033[38;2;80;250;123m'
CYAN='\033[38;2;139;233;253m'
PURPLE='\033[38;2;189;147;249m'
YELLOW='\033[38;2;241;250;140m'
ORANGE='\033[38;2;255;184;108m'
RED='\033[38;2;255;85;85m'
DIM='\033[2m'
RESET='\033[0m'

sep=" ${DIM}|${RESET} "

# --- Line 1: location context ---
line1="${PINK}${dir}${RESET}"
[ -n "$git_branch" ]  && line1+="${sep}${GREEN}${git_branch}${RESET}"
[ -n "$worktree" ]    && line1+="${sep}${ORANGE}wt:${worktree}${RESET}"
[ -n "$agent" ]       && line1+="${sep}${YELLOW}agent:${agent}${RESET}"
[ -n "$vim_mode" ]    && line1+="${sep}${YELLOW}${vim_mode}${RESET}"

# --- Line 2: AI context ---
line2_parts=()
[ -n "$model" ]    && line2_parts+=("${CYAN}${model}${RESET}")
[ -n "$ctx_bar" ]  && line2_parts+=("${PURPLE}ctx:${ctx_bar}${RESET}")
[ -n "$cost_str" ] && line2_parts+=("${GREEN}${cost_str}${RESET}")
[ -n "$duration_str" ] && line2_parts+=("${DIM}${duration_str}${RESET}")
time_str=$(date +%H:%M)
line2_parts+=("${DIM}${time_str}${RESET}")

line2=""
for part in "${line2_parts[@]}"; do
  [ -z "$line2" ] && line2="$part" || line2+="${sep}${part}"
done

# --- Line 3: limits & diffs (only if data exists) ---
line3_parts=()
[ -n "$rate_str" ]  && line3_parts+=("${RED}${rate_str}${RESET}")
[ -n "$lines_str" ] && line3_parts+=("${DIM}lines:${RESET} ${GREEN}+${lines_added}${RESET} ${RED}-${lines_removed}${RESET}")

if [ "${#line3_parts[@]}" -gt 0 ]; then
  line3=""
  for part in "${line3_parts[@]}"; do
    [ -z "$line3" ] && line3="$part" || line3+="${sep}${part}"
  done
  printf "%b\n%b\n%b\n" "$line1" "$line2" "$line3"
else
  printf "%b\n%b\n" "$line1" "$line2"
fi
