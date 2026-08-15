#!/usr/bin/env bash
# Claude/Cursor statusLine renderer — Dracula palette, pair-per-line layout.
# Shared implementation. Thin wrappers in common/claude/.claude/ and
# common/cursor/.cursor/ exec this file so both stay in sync.
#
# Cursor extras (when payload/host looks like Cursor CLI):
#   model.param_summary / max_mode / autorun / session_name
#   ctx threshold colors, width-aware compaction, plan usage from ai-usage cache

input=$(cat)

# Host: wrapper sets STATUSLINE_HOST=claude|cursor. Fall back to payload shape.
host="${STATUSLINE_HOST:-}"
if [ -z "$host" ]; then
  if printf '%s' "$input" | jq -e 'has("autorun") or (.model.max_mode != null) or (.model.param_summary != null)' >/dev/null 2>&1; then
    host=cursor
  else
    host=claude
  fi
fi

__state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/$host"
mkdir -p "$__state_dir" 2>/dev/null
printf '%s' "$input" > "$__state_dir/statusline-input.json" 2>/dev/null || true

# --- Extract fields (single jq pass; \x1f keeps empty fields intact under read) ---
US=$'\x1f'
IFS="$US" read -r cwd model param_summary max_mode used_pct render_width \
  vim_mode worktree agent cost duration_ms lines_added lines_removed \
  session_name autorun version < <(
  printf '%s' "$input" | jq -r --arg us "$US" '
    [
      ((.workspace.current_dir // .cwd // "") | tostring),
      ((.model.display_name // "") | tostring),
      ((.model.param_summary // "") | tostring),
      (if .model.max_mode == true then "1" else "" end),
      ((.context_window.used_percentage // "") | tostring),
      ((.render_width_chars // 0) | tostring),
      ((.vim.mode // "") | tostring),
      ((.worktree.name // .workspace.git_worktree // "") | tostring),
      ((.agent.name // "") | tostring),
      ((.cost.total_cost_usd // "") | tostring),
      ((.cost.total_duration_ms // "") | tostring),
      ((.cost.total_lines_added // "") | tostring),
      ((.cost.total_lines_removed // "") | tostring),
      ((.session_name // "") | tostring),
      (if .autorun == true then "1" else "" end),
      ((.version // "") | tostring)
    ] | join($us)
  '
)

# --- Directory: last 2 components ---
if [ -n "$cwd" ]; then
  home_replaced="${cwd/#$HOME/~}"
  dir=$(printf '%s' "$home_replaced" | awk -F'/' '{
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

# --- Context bar + threshold color ---
ctx_bar=""
ctx_color_name=PURPLE
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct" 2>/dev/null || echo 0)
  [ "$used_int" -gt 100 ] 2>/dev/null && used_int=100
  [ "$used_int" -lt 0 ] 2>/dev/null && used_int=0
  filled=$(( used_int / 10 ))
  empty=$(( 10 - filled ))
  bar=""
  for _ in $(seq 1 "$filled"); do bar="${bar}█"; done
  for _ in $(seq 1 "$empty");  do bar="${bar}░"; done
  ctx_bar="${bar} ${used_int}%"
  if [ "$used_int" -ge 80 ]; then
    ctx_color_name=RED
  elif [ "$used_int" -ge 50 ]; then
    ctx_color_name=YELLOW
  fi
fi

# --- Model label (Cursor: param_summary / MAX) ---
model_label="$model"
if [ -n "$param_summary" ]; then
  # "(Thinking)" → keep as-is beside the name
  model_label="${model_label} ${param_summary}"
fi
[ "$max_mode" = "1" ] && model_label="${model_label} MAX"

# --- Cost / duration / lines (Claude-heavy; Cursor usually empty) ---
cost_str=""
if [ -n "$cost" ] && [ "$cost" != "0" ] && [ "$cost" != "null" ]; then
  cost_str=$(printf '$%.4f' "$cost" 2>/dev/null || true)
fi

duration_str=""
if [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ] && [ "$duration_ms" != "null" ]; then
  secs=$(( ${duration_ms%.*} / 1000 ))
  if [ "$secs" -ge 3600 ]; then
    duration_str=$(printf '%dh%02dm' $(( secs / 3600 )) $(( (secs % 3600) / 60 )))
  else
    duration_str=$(printf '%dm%02ds' $(( secs / 60 )) $(( secs % 60 )))
  fi
fi

lines_str=""
if [ -n "$lines_added" ] && [ -n "$lines_removed" ]; then
  if [ "$lines_added" != "0" ] || [ "$lines_removed" != "0" ]; then
    lines_str="+${lines_added} -${lines_removed}"
  fi
fi

# --- Session name (short) ---
sess_str=""
if [ -n "$session_name" ]; then
  sess_str="$session_name"
  # hard cap; width compaction may shrink further
  if [ "${#sess_str}" -gt 28 ]; then
    sess_str="${sess_str:0:25}…"
  fi
fi

# --- Autorun ---
auto_str=""
[ "$autorun" = "1" ] && auto_str="auto"

# --- Cursor plan usage from ai-usage cache (no network on this path) ---
plan_str=""
if [ "$host" = "cursor" ]; then
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/tmux/cursor_usage"
  if [ -f "$cache" ]; then
    IFS='|' read -r a_pct b_pct reset_field < "$cache" || true
    if [ -n "${a_pct:-}" ] && [ -n "${b_pct:-}" ]; then
      rem=""
      if [ -n "${reset_field:-}" ] && [ "$reset_field" -eq "$reset_field" ] 2>/dev/null; then
        now=$(date +%s)
        secs=$(( reset_field - now ))
        if [ "$secs" -le 0 ]; then
          rem="0m"
        else
          total_min=$(( secs / 60 ))
          h=$(( total_min / 60 ))
          m=$(( total_min % 60 ))
          if [ "$h" -ge 24 ]; then
            rem=$(printf '%dd%dh' $(( h / 24 )) $(( h % 24 )))
          elif [ "$h" -gt 0 ]; then
            rem=$(printf '%dh%02dm' "$h" "$m")
          else
            rem=$(printf '%dm' "$m")
          fi
        fi
      fi
      plan_str="cursor ${a_pct}% · other ${b_pct}%"
      [ -n "$rem" ] && plan_str="${plan_str} ${rem}"
    fi
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

ctx_color="$PURPLE"
case "$ctx_color_name" in
  RED) ctx_color="$RED" ;;
  YELLOW) ctx_color="$YELLOW" ;;
esac

sep_raw=" ${DIM}|${RESET} "
sep_plain=" | "

parts_raw=()
parts_plain=()

add_part() {
  local raw="$1" plain="$2"
  [ -z "$plain" ] && return
  parts_raw+=("$raw")
  parts_plain+=("$plain")
}

# Width tiers: detailed (>=100) / balanced (>=70) / minimal (<70)
width=${render_width:-0}
# jq may emit empty; treat as wide enough for detailed
case "$width" in ''|*[!0-9]*) width=120 ;; esac

if [ "$width" -lt 70 ]; then
  # minimal: model + ctx only (plus plan % if Cursor)
  add_part "${CYAN}${model_label}${RESET}" "${model_label}"
  [ -n "$ctx_bar" ] && add_part "${ctx_color}ctx:${ctx_bar}${RESET}" "ctx:${ctx_bar}"
  [ -n "$plan_str" ] && add_part "${ORANGE}${plan_str}${RESET}" "${plan_str}"
elif [ "$width" -lt 100 ]; then
  # balanced: dir/branch/model/ctx + compact extras
  add_part "${PINK}${dir}${RESET}" "${dir}"
  add_part "${GREEN}${git_branch}${RESET}" "${git_branch}"
  add_part "${CYAN}${model_label}${RESET}" "${model_label}"
  [ -n "$ctx_bar" ] && add_part "${ctx_color}ctx:${ctx_bar}${RESET}" "ctx:${ctx_bar}"
  [ -n "$plan_str" ] && add_part "${ORANGE}${plan_str}${RESET}" "${plan_str}"
  [ -n "$auto_str" ] && add_part "${YELLOW}${auto_str}${RESET}" "${auto_str}"
  [ -n "$vim_mode" ] && add_part "${YELLOW}${vim_mode}${RESET}" "${vim_mode}"
else
  # detailed
  add_part "${PINK}${dir}${RESET}" "${dir}"
  add_part "${GREEN}${git_branch}${RESET}" "${git_branch}"
  add_part "${CYAN}${model_label}${RESET}" "${model_label}"
  [ -n "$ctx_bar" ] && add_part "${ctx_color}ctx:${ctx_bar}${RESET}" "ctx:${ctx_bar}"

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

  [ -n "$plan_str" ] && add_part "${ORANGE}${plan_str}${RESET}" "${plan_str}"
  [ -n "$sess_str" ] && add_part "${DIM}${sess_str}${RESET}" "${sess_str}"
  [ -n "$worktree" ] && add_part "${ORANGE}wt:${worktree}${RESET}" "wt:${worktree}"
  [ -n "$agent" ]    && add_part "${YELLOW}agent:${agent}${RESET}" "agent:${agent}"
  [ -n "$auto_str" ] && add_part "${YELLOW}${auto_str}${RESET}" "${auto_str}"
  [ -n "$vim_mode" ] && add_part "${YELLOW}${vim_mode}${RESET}"    "${vim_mode}"
fi

# --- Pair parts into lines (2 per line; minimal stays denser at 2 still) ---
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
