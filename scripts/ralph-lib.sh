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
