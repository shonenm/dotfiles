#!/usr/bin/env bash
# Claude/Cursor statusLine renderer — Dracula palette, pair-per-line layout.
# Shared implementation. Thin wrappers in common/claude/.claude/ and
# common/cursor/.cursor/ exec this file so both stay in sync.

input=$(cat)
__state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude"
mkdir -p "$__state_dir" 2>/dev/null
echo "$input" > "$__state_dir/statusline-input.json"

# --- Extract fields (single jq pass; \x1f separator keeps empty fields intact under read) ---
US=$'\x1f'
IFS="$US" read -r cwd model used_pct vim_mode worktree agent cost duration_ms lines_added lines_removed < <(
  printf '%s' "$input" | jq -r --arg us "$US" '
    [ ((.workspace.current_dir // .cwd // "")           | tostring),
      ((.model.display_name // "")                       | tostring),
      ((.context_window.used_percentage // "")           | tostring),
      ((.vim.mode // "")                                 | tostring),
      ((.worktree.name // .workspace.git_worktree // "") | tostring),
      ((.agent.name // "")                               | tostring),
      ((.cost.total_cost_usd // "")                      | tostring),
      ((.cost.total_duration_ms // "")                   | tostring),
      ((.cost.total_lines_added // "")                   | tostring),
      ((.cost.total_lines_removed // "")                 | tostring)
    ] | join($us)
  '
)

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

sep_raw=" ${DIM}|${RESET} "
sep_plain=" | "

# --- Collect ordered parts: (colored, plain) pairs ---
parts_raw=()
parts_plain=()

add_part() {
  local raw="$1" plain="$2"
  [ -z "$plain" ] && return
  parts_raw+=("$raw")
  parts_plain+=("$plain")
}

add_part "${PINK}${dir}${RESET}"                        "${dir}"
add_part "${GREEN}${git_branch}${RESET}"                "${git_branch}"
add_part "${CYAN}${model}${RESET}"                      "${model}"
[ -n "$ctx_bar" ] && add_part "${PURPLE}ctx:${ctx_bar}${RESET}" "ctx:${ctx_bar}"

# Combined usage: cost + duration + diff lines
usage_raw=""
usage_plain=""
append_usage() {
  local raw="$1" plain="$2"
  [ -z "$plain" ] && return
  if [ -z "$usage_plain" ]; then
    usage_raw="$raw"; usage_plain="$plain"
  else
    usage_raw="${usage_raw} ${raw}"
    usage_plain="${usage_plain} ${plain}"
  fi
}
append_usage "${GREEN}${cost_str}${RESET}"   "${cost_str}"
append_usage "${DIM}${duration_str}${RESET}" "${duration_str}"
if [ -n "$lines_str" ]; then
  append_usage "${GREEN}+${lines_added}${RESET}${DIM}/${RESET}${RED}-${lines_removed}${RESET}" "+${lines_added}/-${lines_removed}"
fi
add_part "$usage_raw" "$usage_plain"

[ -n "$worktree" ] && add_part "${ORANGE}wt:${worktree}${RESET}" "wt:${worktree}"
[ -n "$agent" ]    && add_part "${YELLOW}agent:${agent}${RESET}" "agent:${agent}"
[ -n "$vim_mode" ] && add_part "${YELLOW}${vim_mode}${RESET}"    "${vim_mode}"

# --- Pair parts into lines (2 per line) ---
lines_raw=()
lines_plain=()
n=${#parts_raw[@]}
i=0
while [ "$i" -lt "$n" ]; do
  j=$(( i + 1 ))
  if [ "$j" -lt "$n" ]; then
    lines_raw+=("${parts_raw[$i]}${sep_raw}${parts_raw[$j]}")
    lines_plain+=("${parts_plain[$i]}${sep_plain}${parts_plain[$j]}")
  else
    lines_raw+=("${parts_raw[$i]}")
    lines_plain+=("${parts_plain[$i]}")
  fi
  i=$(( i + 2 ))
done

# --- Pad lines to equal visible width ---
max_len=0
for p in "${lines_plain[@]}"; do
  [ "${#p}" -gt "$max_len" ] && max_len=${#p}
done

for idx in "${!lines_raw[@]}"; do
  plain_len=${#lines_plain[idx]}
  pad=$(( max_len - plain_len ))
  if [ "$pad" -gt 0 ]; then
    spaces=$(printf '%*s' "$pad" '')
    lines_raw[idx]="${lines_raw[idx]}${spaces}"
  fi
done

# --- Output ---
for line in "${lines_raw[@]}"; do
  printf '%b\n' "$line"
done
