#!/bin/bash
# install-common.sh - mac.sh と linux.sh で共通の Claude/agent 系インストール関数。
# 両 installer から source される。utils.sh の log_* ヘルパーに依存するため
# utils.sh を source した後に読み込むこと。定義のみで、呼び出しは各 installer の main が行う。
# shellcheck shell=bash

# Rust ツール (tools/ workspace: ai-usage / wt / pomodoro) をビルドして ~/.local/bin へ。
# build 失敗時は当該 binary が欠けるだけの degrade (run_step が失敗を収集し installer は継続)。
install_rust_tools() {
  if ! command_exists cargo; then
    log_warn "cargo not found, skipping rust tools (ai-usage / wt / pomodoro)"
    return
  fi
  log_info "Building rust tools (ai-usage / wt / pomodoro)..."
  if cargo build --release --manifest-path "$DOTFILES_DIR/tools/Cargo.toml"; then
    mkdir -p "$HOME/.local/bin"
    local b
    for b in ai-usage wt pomodoro; do
      install "$DOTFILES_DIR/tools/target/release/$b" "$HOME/.local/bin/"
    done
    log_success "rust tools installed to ~/.local/bin"
  else
    log_warn "rust tools build failed — ai-usage/wt/pomodoro は使用不可 (旧 bash は削除済みで fallback なし)"
  fi
}

install_npm_packages() {
  if ! command_exists npm; then
    log_warn "npm not found, skipping npm packages"
    return
  fi

  local npm_file="$CONFIG_DIR/packages.npm.txt"
  if [[ ! -f "$npm_file" ]]; then
    log_warn "NPM package list not found: $npm_file"
    return
  fi

  log_info "Installing npm packages..."
  while IFS= read -r pkg; do
    if ! npm list -g "$pkg" &>/dev/null; then
      log_info "Installing $pkg..."
      npm install -g "$pkg"
    else
      log_success "$pkg already installed"
    fi
  done < <(read_package_list "$npm_file")
}

install_claude_mem() {
  if ! command_exists npx; then
    log_warn "npx not found, skipping claude-mem"
    return
  fi

  if [[ -f "$HOME/.claude-mem/settings.json" ]]; then
    log_success "claude-mem already installed"
  else
    log_info "Installing claude-mem..."
    npx -y claude-mem install
  fi

  disable_claude_mem_stop_hook
}

disable_claude_mem_stop_hook() {
  if ! command_exists jq; then
    log_warn "jq not found, skipping claude-mem Stop hook patch"
    return
  fi

  local patched=false
  local hooks_json
  for hooks_json in "$HOME"/.claude/plugins/cache/thedotmack/claude-mem/*/hooks/hooks.json; do
    [[ -f "$hooks_json" ]] || continue

    if [[ "$(jq -r 'has("hooks") and (.hooks | has("Stop"))' "$hooks_json" 2>/dev/null)" != "true" ]]; then
      continue
    fi

    local tmp="${hooks_json}.tmp.$$"
    if jq 'del(.hooks.Stop)' "$hooks_json" > "$tmp" && mv "$tmp" "$hooks_json"; then
      log_success "Disabled claude-mem Stop hook: $hooks_json"
      patched=true
    else
      rm -f "$tmp"
      log_warn "Failed to patch claude-mem Stop hook: $hooks_json"
    fi
  done

  if [[ "$patched" == "false" ]]; then
    log_success "claude-mem Stop hook already disabled"
  fi
}

install_serena() {
  if ! command_exists uv; then
    log_warn "uv not found, skipping serena"
    return
  fi

  if command_exists serena; then
    log_success "Serena MCP already installed"
    return
  fi

  log_info "Installing Serena MCP (LSP-based semantic code search)..."
  uv tool install -p 3.13 serena-agent@latest --prerelease=allow
  log_success "Serena MCP installed"
}

install_context_mode() {
  if ! command_exists claude; then
    log_warn "claude CLI not found, skipping context-mode"
    return
  fi

  if claude plugin list 2>/dev/null | grep -q "context-mode@context-mode"; then
    log_success "context-mode plugin already installed"
    return
  fi

  log_info "Installing Context Mode Claude Code plugin..."
  if ! claude plugin marketplace list 2>/dev/null | grep -q "^  ❯ context-mode$"; then
    claude plugin marketplace add mksglu/context-mode
  fi
  claude plugin install context-mode@context-mode
  log_success "context-mode plugin installed"
}

install_code_review_graph() {
  if ! command_exists uv; then
    log_warn "uv not found, skipping code-review-graph"
    return
  fi

  if command_exists code-review-graph; then
    log_success "code-review-graph already installed"
    return
  fi

  log_info "Installing code-review-graph (PR review blast-radius analyzer)..."
  uv tool install code-review-graph
  log_success "code-review-graph installed (run 'crg-daemon add <path>' per project to enable)"
}

install_auto_mode() {
  if ! command_exists jq; then
    log_warn "jq not found, skipping auto mode default"
    return
  fi

  local settings="$HOME/.claude/settings.json"
  [[ -f "$settings" ]] || echo '{}' > "$settings"

  if [[ "$(jq -r '.permissions.defaultMode // ""' "$settings" 2>/dev/null)" == "auto" ]]; then
    log_success "Claude auto mode already set as default"
    return
  fi

  log_info "Setting Claude auto mode as default..."
  local tmp="${settings}.tmp"
  jq '.permissions //= {} | .permissions.defaultMode = "auto"' "$settings" > "$tmp" && mv "$tmp" "$settings"
  log_success "Claude auto mode set as default"
}

install_gh_extensions() {
  if ! command_exists gh; then
    log_warn "gh CLI not found, skipping gh extensions"
    return
  fi

  if ! gh auth status &>/dev/null; then
    log_warn "gh CLI not authenticated, skipping gh extensions"
    return
  fi

  if gh extension list | grep -q "dlvhdr/gh-dash"; then
    log_success "gh-dash already installed"
  else
    log_info "Installing gh-dash extension..."
    if gh extension install dlvhdr/gh-dash; then
      log_success "gh-dash installed"
    else
      log_error "Failed to install gh-dash"
    fi
  fi
}

