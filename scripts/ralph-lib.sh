#!/usr/bin/env bash
# ralph-lib.sh - Shared utilities for ralph-orchestrate and ralph-crew
#
# Usage: source this file in your scripts
#   source "$(dirname "$0")/ralph-lib.sh"

# Default permissions JSON for ralph workers
readonly RALPH_DEFAULT_PERMISSIONS='{
  "allow": [
    "Bash(git add:*)",
    "Bash(git commit:*)",
    "Bash(git diff:*)",
    "Bash(git status:*)",
    "Bash(git log:*)",
    "Bash(git branch:*)",
    "Bash(git checkout:*)",
    "Bash(git stash:*)",
    "Bash(git show:*)",
    "Bash(git ls-files:*)",
    "Bash(git ls-tree:*)",
    "Bash(gh issue:*)",
    "Bash(gh pr:*)",
    "Bash(gh api:*)",
    "Bash(cat:*)",
    "Bash(ls:*)",
    "Bash(tree:*)",
    "Bash(wc:*)",
    "Bash(grep:*)",
    "Bash(find:*)",
    "Bash(readlink:*)",
    "Bash(bash:*)",
    "Bash(npm:*)",
    "Bash(npx:*)",
    "Bash(cargo:*)",
    "Bash(python3:*)",
    "Bash(shellcheck:*)",
    "Bash(chmod:*)",
    "Bash(stow:*)",
    "Bash(git worktree:*)",
    "WebSearch"
  ],
  "deny": [
    "Bash(git push:*)",
    "Bash(git push)"
  ]
}'

# Setup worker settings.local.json in the specified directory.
#
# Usage:
#   ralph_setup_worker_settings <project_dir> [permissions_json] [extra_settings_json]
#
# Args:
#   project_dir:          Directory where .claude/settings.local.json will be created
#   permissions_json:     JSON object with "allow" and "deny" arrays (optional, uses defaults)
#   extra_settings_json:  Additional JSON to merge into settings (optional, e.g. hooks)
ralph_setup_worker_settings() {
  local project_dir="$1"
  local permissions_json="${2:-$RALPH_DEFAULT_PERMISSIONS}"
  local extra_settings_json="${3:-}"
  local settings_dir="${project_dir}/.claude"
  mkdir -p "$settings_dir"

  local settings_file="${settings_dir}/settings.local.json"
  local backup_file="${settings_file}.pre-ralph-crew"

  # Preserve any pre-existing user settings so teardown can restore them.
  # Only snapshot on the first overwrite (restart/re-init must not clobber
  # the original backup with an already-worker-scoped settings file).
  if [[ -f "$settings_file" && ! -f "$backup_file" ]]; then
    cp "$settings_file" "$backup_file"
  fi

  if [[ -n "$extra_settings_json" ]]; then
    # Merge permissions + extra settings
    jq -n \
      --argjson perms "$permissions_json" \
      --argjson extra "$extra_settings_json" \
      '{"permissions": $perms} * $extra' \
      > "$settings_file"
  else
    jq -n --argjson perms "$permissions_json" '{"permissions": $perms}' > "$settings_file"
  fi
}

# Pre-populate Claude Code's project-local trust state so a freshly-launched
# worker does not block on any first-launch interactive dialog. Covers both:
#
#   1. "Quick safety check" project trust dialog
#      -> .projects[<abs_path>].hasTrustDialogAccepted = true
#
#   2. "New MCP server found in .mcp.json: <name>" approval dialog
#      -> .projects[<abs_path>].enabledMcpjsonServers += [<name>...]
#
# --dangerously-skip-permissions does NOT suppress either dialog, so unattended
# operation (launchd / tmux-resident ralph-crew daemon) requires writing both
# acceptances up-front.
#
# Usage:
#   ralph_preaccept_trust <project_dir>
#
# Idempotent. No-ops when ~/.claude.json does not exist (Claude will create it
# on first launch with trust already set by this function's output).
ralph_preaccept_trust() {
  local project_dir="$1"
  local claude_config="${HOME}/.claude.json"

  [[ -f "$claude_config" ]] || return 0

  local abs_dir
  abs_dir="$(cd "$project_dir" 2>/dev/null && pwd -P)" || return 1

  # Collect MCP server names declared in the project's .mcp.json so they can be
  # pre-approved. Empty array when the project has no .mcp.json.
  local mcp_servers_json='[]'
  local mcp_file="${abs_dir}/.mcp.json"
  if [[ -f "$mcp_file" ]]; then
    mcp_servers_json="$(jq -c '(.mcpServers // {}) | keys' "$mcp_file" 2>/dev/null || echo '[]')"
  fi

  local tmp="${claude_config}.ralph-tmp.$$"
  if jq --arg d "$abs_dir" --argjson servers "$mcp_servers_json" '
    .bypassPermissionsModeAccepted = true |
    .projects[$d] = ((.projects[$d] // {}) + {
      hasTrustDialogAccepted: true,
      hasCompletedProjectOnboarding: true
    }) |
    .projects[$d].enabledMcpjsonServers = (
      ((.projects[$d].enabledMcpjsonServers // []) + $servers) | unique
    ) |
    .projects[$d].disabledMcpjsonServers = (
      ((.projects[$d].disabledMcpjsonServers // []) - $servers) | unique
    )
  ' "$claude_config" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$claude_config"
  else
    rm -f "$tmp"
    return 1
  fi
}

# fix タスクを持つ worker の権限を調整: git push を allow、force push のみ deny。
# allow/deny を dedup (再 init や重複ルールで増殖しないよう)。Claude 所有スキーマの
# jq 操作なので Go でなく bash に温存する (Go crew は CLI 経由で呼ぶ)。
ralph_adjust_permissions_for_fix() {
  local permissions_json="$1"
  if [[ -z "$permissions_json" || "$permissions_json" == "null" ]]; then
    permissions_json="$RALPH_DEFAULT_PERMISSIONS"
  fi
  echo "$permissions_json" | jq '
    .deny = ([.deny[]? | select(
      (. == "Bash(git push:*)" or . == "Bash(git push)") | not
    )] + ["Bash(git push --force:*)", "Bash(git push -f:*)"] | unique) |
    .allow = ((.allow // []) + ["Bash(git worktree:*)", "Bash(git push:*)", "Bash(gh pr:*)"] | unique)
  '
}

# --- Dual-mode: sourced ならライブラリ、実行されたら CLI (Go crew 用) ---
# Go crew は Claude 所有スキーマの jq 操作を再実装せず、この CLI に shell-out する。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  case "${1:-}" in
    setup-worker)
      # setup-worker <project_dir> <permissions_json|""> <hook_json> <has_fix:0|1>
      _pd="${2:?project_dir required}"
      _perms="${3:-}"
      _hook="${4:-}"
      _has_fix="${5:-0}"
      if [[ -z "$_perms" || "$_perms" == "null" ]]; then
        _perms="$RALPH_DEFAULT_PERMISSIONS"
      fi
      if [[ "$_has_fix" == "1" ]]; then
        _perms="$(ralph_adjust_permissions_for_fix "$_perms")"
      fi
      ralph_setup_worker_settings "$_pd" "$_perms" "$_hook"
      ;;
    preaccept-trust)
      ralph_preaccept_trust "${2:?worker_cwd required}"
      ;;
    *)
      echo "usage: ralph-lib.sh <setup-worker|preaccept-trust> ..." >&2
      exit 2
      ;;
  esac
fi
