#!/bin/bash
# Claude Code API fallback manager
# Usage: claude-fallback.sh <on|off|status|setup>
#
# Anthropic API障害時にOpenRouter経由でClaude Codeを使うための切替スクリプト。
# .zshrc.common の claude() ラッパー関数と連携して動作する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-fallback"
FLAG_FILE="$DATA_DIR/active"
ENV_FILE="$DATA_DIR/env"

# Source utilities if available
if [[ -f "$SCRIPT_DIR/utils.sh" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/utils.sh"
else
  log_info()    { echo "[INFO] $1"; }
  log_success() { echo "[OK] $1"; }
  log_warn()    { echo "[WARN] $1"; }
  log_error()   { echo "[ERROR] $1"; }
fi

# --- setup: 1PasswordからOpenRouter APIキーを取得してキャッシュ ---
cmd_setup() {
  if ! command -v op &>/dev/null; then
    log_error "1Password CLI not found"
    return 1
  fi

  if ! op whoami &>/dev/null; then
    log_error "1Password not signed in (run 'eval \$(op signin)' first)"
    return 1
  fi

  local openrouter_key
  openrouter_key=$(op read "op://Personal/OpenRouter API/credential" 2>/dev/null) || {
    log_error "Failed to get OpenRouter API key from 1Password"
    return 1
  }

  mkdir -p "$DATA_DIR"
  echo "OPENROUTER_API_KEY=$openrouter_key" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log_success "OpenRouter API key cached"
}

# --- on: フォールバックモードを有効化 ---
cmd_on() {
  if [[ ! -f "$ENV_FILE" ]]; then
    log_error "API key not cached. Run 'claude-fallback.sh setup' first."
    return 1
  fi

  mkdir -p "$DATA_DIR"
  touch "$FLAG_FILE"

  # Slack通知(非同期)
  "$SCRIPT_DIR/ai-notify.sh" claude fallback &>/dev/null &

  echo ""
  log_success "Fallback mode: ON (OpenRouter)"
  log_info "claude -c で前のセッションを再開できます"
}

# --- off: フォールバックモードを無効化 ---
cmd_off() {
  rm -f "$FLAG_FILE"

  # Slack通知(非同期)
  "$SCRIPT_DIR/ai-notify.sh" claude recovered &>/dev/null &

  echo ""
  log_success "Fallback mode: OFF (Subscription)"
  log_info "次回の claude 起動からサブスクリプション認証に復帰します"
}

# --- status: 現在のモード表示 + ヘルスチェック ---
cmd_status() {
  echo "=== Claude Code Fallback Status ==="

  # モード表示
  if [[ -f "$FLAG_FILE" ]]; then
    log_warn "Mode: FALLBACK (OpenRouter)"
  else
    log_success "Mode: NORMAL (Subscription)"
  fi

  # APIキーキャッシュ
  if [[ -f "$ENV_FILE" ]]; then
    log_success "API key: cached"
  else
    log_warn "API key: not cached (run 'claude-fallback.sh setup')"
  fi

  # Anthropic APIヘルスチェック
  echo ""
  log_info "Checking Anthropic API..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://api.anthropic.com/v1/messages" 2>/dev/null) || http_code="000"

  # 401 = API自体は稼働中(認証エラーは正常応答)
  if [[ "$http_code" == "401" ]]; then
    log_success "Anthropic API: reachable (HTTP $http_code)"
  elif [[ "$http_code" == "000" ]]; then
    log_error "Anthropic API: unreachable (timeout/connection error)"
  else
    log_warn "Anthropic API: HTTP $http_code"
  fi
}

# --- Main ---
case "${1:-help}" in
  setup)  cmd_setup ;;
  on)     cmd_on ;;
  off)    cmd_off ;;
  status) cmd_status ;;
  help|*)
    echo "Usage: claude-fallback.sh <command>"
    echo ""
    echo "Commands:"
    echo "  on      Enable fallback mode (OpenRouter)"
    echo "  off     Disable fallback mode (back to Subscription)"
    echo "  status  Show current mode and API health"
    echo "  setup   Cache OpenRouter API key from 1Password"
    ;;
esac
