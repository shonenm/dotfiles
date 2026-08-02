#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

command_exists() {
  command -v "$1" &>/dev/null
}

npm_package_name() {
  local spec="$1"
  if [[ "$spec" == @*/*@* ]]; then
    echo "${spec%@*}"
  elif [[ "$spec" == @*/* ]]; then
    echo "$spec"
  else
    echo "${spec%%@*}"
  fi
}

# Fetch the global npm inventory once instead of starting npm for every package.
npm_global_packages() {
  npm list -g --depth=0 --json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except (ValueError, OSError):
    raise SystemExit(0)
for name in data.get("dependencies", {}):
    print(name)
'
}

list_contains_line() {
  local list="$1" value="$2"
  grep -Fxq -- "$value" <<< "$list"
}

# True when TARGET is missing or any file below one of INPUTS is newer.
target_needs_rebuild() {
  local target="$1"
  shift
  [[ -x "$target" ]] || return 0

  local input
  for input in "$@"; do
    [[ -e "$input" ]] || continue
    if [[ -d "$input" ]]; then
      [[ -n "$(find "$input" -type f -newer "$target" -print -quit 2>/dev/null)" ]] && return 0
    elif [[ "$input" -nt "$target" ]]; then
      return 0
    fi
  done
  return 1
}

install_fingerprint() {
  local value path
  for value in "$@"; do
    if [[ "$value" == file:* ]]; then
      path="${value#file:}"
      if [[ -f "$path" ]]; then
        git hash-object "$path"
      else
        echo missing
      fi
    else
      printf '%s\n' "$value"
    fi
  done | git hash-object --stdin
}

install_state_is_current() {
  local key="$1" fingerprint="$2"
  [[ "${UPDATE_INSTALL:-false}" != "true" ]] || return 1
  local state_file="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-install/$key"
  [[ -f "$state_file" ]] && [[ "$(<"$state_file")" == "$fingerprint" ]]
}

record_install_state() {
  local key="$1" fingerprint="$2"
  local state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-install"
  mkdir -p "$state_dir"
  printf '%s\n' "$fingerprint" > "$state_dir/$key"
}

# Render SRC after replacing __HOME__, but avoid rewriting an unchanged target.
render_home_template() {
  local src="$1" dst="$2" tmp
  mkdir -p "$(dirname "$dst")"
  tmp=$(mktemp)
  sed "s|__HOME__|$HOME|g" "$src" > "$tmp"
  if [[ -f "$dst" ]] && cmp -s "$tmp" "$dst"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$dst"
}

# --- Install step failure tracking ---
# run_step records failures instead of aborting, so one broken step doesn't
# stop the rest of the setup but the script can still exit non-zero.
# Usage:
#   run_step install_foo
#   run_step install_bar
#   finish_steps "All packages installed!"   # exits 1 if any step failed
# (string accumulation instead of an array: empty arrays break under
#  `set -u` on macOS bash 3.2)
FAILED_STEPS=""
STEP_TIMINGS=""
run_step() {
  local step="$1" started=$SECONDS status=0
  if ! "$step"; then
    status=1
    FAILED_STEPS="${FAILED_STEPS} $1"
    log_error "Step failed: $1"
  fi
  STEP_TIMINGS="${STEP_TIMINGS}${step}:$((SECONDS - started))s "
  return "$status"
}

finish_steps() {
  local success_msg="$1"
  [[ -n "$STEP_TIMINGS" ]] && log_info "Step timings: $STEP_TIMINGS"
  if [[ -n "$FAILED_STEPS" ]]; then
    log_error "Setup finished with failed steps:${FAILED_STEPS}"
    return 1
  fi
  log_success "$success_msg"
}

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}

# sudo が実質的に利用可能かを非対話で判定する
# 戻り値: 0 = NO_SUDO (sudo使えない or 不要), 1 = SUDO利用可
# 判定順:
#   1. EUID=0 (既に root) → sudo不要だが従来パスで進める → return 1
#   2. sudo バイナリなし → NO_SUDO → return 0
#   3. `sudo -n true` 成功 (NOPASSWD or ticket有効) → SUDO利用可 → return 1
#   4. それ以外 (sudoあるがパスワード要求) → NO_SUDO → return 0
detect_sudo_mode() {
  if [[ $EUID -eq 0 ]]; then
    return 1
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    return 0
  fi
  if sudo -n true 2>/dev/null; then
    return 1
  fi
  return 0
}

# Read a newline-delimited package list file, stripping comments and blank lines
# Usage: readarray -t MY_ARRAY < <(read_package_list "$file")
read_package_list() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    log_error "Package list not found: $file"
    return 1
  fi
  grep -v '^\s*#' "$file" | grep -v '^\s*$'
}

# Enable Claude Code Remote Control auto-start by patching ~/.claude.json.
# ~/.claude.json is a runtime file (not dotfile-managed), so this is applied at
# install time to make mobile control work on every fresh environment.
configure_claude_remote_control_autostart() {
  local claude_json="$HOME/.claude.json"

  if ! command_exists jq; then
    log_warn "jq not found; skipping Claude remote control auto-start"
    return
  fi

  if [[ ! -f "$claude_json" ]]; then
    log_info "$claude_json not present yet; run 'claude' once, then rerun install"
    return
  fi

  local current
  current="$(jq -r '.remoteControlAtStartup // false' "$claude_json" 2>/dev/null)"
  if [[ "$current" == "true" ]]; then
    log_success "Claude remote control auto-start already enabled"
    return
  fi

  local tmp="${claude_json}.tmp.$$"
  if jq '.remoteControlAtStartup = true' "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"; then
    log_success "Claude remote control auto-start enabled"
  else
    rm -f "$tmp"
    log_warn "Failed to patch $claude_json"
  fi
}
