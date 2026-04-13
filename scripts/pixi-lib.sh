#!/bin/bash
# pixi bootstrap & package installation library (no-sudo mode)
#
# Usage: source this file from install scripts when operating in no-sudo mode.
# Requires: log_info, log_success, log_warn, log_error, command_exists, read_package_list

# PIXI_HOME defaults to ~/.pixi (pixi's own default), exe goes to ~/.pixi/bin
export PIXI_HOME="${PIXI_HOME:-$HOME/.pixi}"
PIXI_BIN="$PIXI_HOME/bin"

# Ensure PATH is set for current session so we can invoke pixi immediately after install
_pixi_ensure_path() {
  case ":$PATH:" in
    *":$PIXI_BIN:"*) ;;
    *) export PATH="$PIXI_BIN:$PATH" ;;
  esac
}

# Install pixi itself if missing (user-scope, no sudo)
install_pixi() {
  _pixi_ensure_path

  if command_exists pixi; then
    log_success "pixi already installed ($(pixi --version 2>/dev/null | head -1))"
    return 0
  fi

  log_info "Installing pixi (user-scope, no sudo required)..."
  if ! curl -fsSL https://pixi.sh/install.sh | sh; then
    log_error "Failed to install pixi"
    return 1
  fi

  _pixi_ensure_path

  if ! command_exists pixi; then
    log_error "pixi installed but not found on PATH ($PIXI_BIN)"
    return 1
  fi

  log_success "pixi installed to $PIXI_HOME"
}

# Check if a package is already installed as a pixi global tool
_pixi_has_package() {
  local pkg="$1"
  pixi global list 2>/dev/null | grep -qE "^[[:space:]]*${pkg}([[:space:]]|\$)" ||
    pixi global list 2>/dev/null | grep -qE "^-[[:space:]]+${pkg}([[:space:]]|:|\$)"
}

# Install packages listed in config/pixi-packages.txt as global tools
# Usage: install_pixi_packages <path-to-pixi-packages.txt>
install_pixi_packages() {
  local pkg_file="${1:-}"
  if [[ -z "$pkg_file" || ! -f "$pkg_file" ]]; then
    log_error "pixi package list not found: $pkg_file"
    return 1
  fi

  if ! command_exists pixi; then
    log_error "pixi not available — run install_pixi first"
    return 1
  fi

  local _new=() _existing=() _failed=()
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    if _pixi_has_package "$pkg"; then
      _existing+=("$pkg")
      continue
    fi
    log_info "Installing $pkg via pixi..."
    if pixi global install "$pkg" >/dev/null 2>&1; then
      _new+=("$pkg")
    else
      log_warn "  Failed to install $pkg via pixi"
      _failed+=("$pkg")
    fi
  done < <(read_package_list "$pkg_file")

  echo
  log_info "── pixi Package Summary ──"
  [[ ${#_new[@]} -gt 0 ]] && log_success "  New: ${_new[*]}"
  [[ ${#_existing[@]} -gt 0 ]] && log_info "  Existing: ${_existing[*]}"
  [[ ${#_failed[@]} -gt 0 ]] && log_warn "  Failed: ${_failed[*]}"

  # Return failure if any package failed
  [[ ${#_failed[@]} -eq 0 ]]
}
