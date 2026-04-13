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
