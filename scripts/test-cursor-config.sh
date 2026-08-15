#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 - "$root/templates/cursor-cli-config.json" "$root/templates/cursor-hooks.json" <<'PY'
import json, sys

cli = json.loads(open(sys.argv[1]).read())
hooks = json.loads(open(sys.argv[2]).read())

deny = cli["permissions"]["deny"]
for pattern in (
    "Read(**/.env)",
    "Read(**/.env.*)",
    "Read(~/.local/share/ai-notify/**)",
    "Shell(sudo **)",
    "Shell(git push --force**)",
):
    assert pattern in deny, pattern
assert cli["approvalMode"] == "unrestricted"
assert cli["statusLine"]["command"].endswith("/.cursor/statusline-command.sh")

assert hooks["version"] == 1
events = hooks["hooks"]
for name in ("sessionStart", "beforeSubmitPrompt", "beforeShellExecution",
             "stop", "sessionEnd"):
    assert name in events, name
commands = [item["command"] for item in events["beforeShellExecution"]]
assert any(cmd.endswith("/block-tmp.sh") for cmd in commands), commands
stop = [item["command"] for item in events["stop"]]
assert any("ai-notify.sh cursor complete" in cmd for cmd in stop), stop
assert any("tmux-claude-pane.sh clear" in item["command"] for item in events["sessionEnd"])
PY

block_tmp="$root/common/claude/.claude/hooks/block-tmp.sh"
chmod +x "$block_tmp"
assert_block_tmp() {
  local input="$1" expected="$2" status=0
  printf '%s' "$input" | "$block_tmp" >/dev/null 2>&1 || status=$?
  [[ "$status" -eq "$expected" ]] || {
    echo "block-tmp expected $expected, got $status for $input" >&2
    exit 1
  }
}
assert_block_tmp '{"tool_name":"Bash","tool_input":{"command":"cat /tmp/x"}}' 2
assert_block_tmp '{"command":"cat /tmp/x"}' 2
assert_block_tmp '{"command":"ls"}' 0
assert_block_tmp '{"tool_name":"Read","tool_input":{"command":"cat /tmp/x"}}' 0

HOME="$tmp/home"
# shellcheck disable=SC1091
source "$root/install.sh"
src="$tmp/source/common/agent/.config/agent/skills"
dest="$HOME/.cursor/skills"
mkdir -p "$src"/{new,managed,external,plain} "$dest/plain"
ln -s "/old/common/agent/.config/agent/skills/managed" "$dest/managed"
ln -s "/external/skills/external" "$dest/external"
link_runtime_skills "$src" "$dest" "Cursor"
[[ "$(readlink "$dest/new")" == "$src/new" ]]
[[ "$(readlink "$dest/managed")" == "$src/managed" ]]
[[ "$(readlink "$dest/external")" == "/external/skills/external" ]]
[[ -d "$dest/plain" && ! -L "$dest/plain" ]]

[[ "$(CURSOR_CONFIG_DIR= XDG_CONFIG_HOME= ; cursor_config_dir)" == "$HOME/.cursor" ]]
[[ "$(XDG_CONFIG_HOME=/x ; cursor_config_dir)" == "/x/cursor" ]]
[[ "$(CURSOR_CONFIG_DIR=/c XDG_CONFIG_HOME=/x ; cursor_config_dir)" == "/c" ]]

mkdir -p "$tmp/cli"
cat > "$tmp/cli/template.json" <<'EOF'
{
  "approvalMode": "allowlist",
  "statusLine": {"command": "__HOME__/.cursor/statusline-command.sh"},
  "display": {"showStatusLineRunningTime": true}
}
EOF
cat > "$tmp/cli/live.json" <<'EOF'
{
  "authInfo": {"email": "keep@example.com"},
  "approvalMode": "unrestricted",
  "display": {"mode": "zen", "showStatusLineRunningTime": false}
}
EOF
write_cursor_cli_config "$tmp/cli/template.json" "$tmp/cli/live.json"
python3 - "$tmp/cli/live.json" "$HOME" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read())
assert data["authInfo"]["email"] == "keep@example.com"
assert data["approvalMode"] == "allowlist"
assert data["display"]["mode"] == "zen"
assert data["display"]["showStatusLineRunningTime"] is True
assert data["statusLine"]["command"] == f"{sys.argv[2]}/.cursor/statusline-command.sh"
PY
if write_cursor_cli_config "$tmp/cli/template.json" "$tmp/cli/live.json"; then
  echo "unchanged cursor cli-config was rewritten" >&2
  exit 1
fi

mkdir -p "$tmp/mcp"
cat > "$tmp/mcp/agent.json" <<'EOF'
{
  "mcpServers": {
    "woodpecker-ci": {
      "type": "stdio",
      "command": "woodpecker-mcp",
      "args": ["serve"],
      "description": "ci",
      "enabled": true
    },
    "tmux": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "tmux-mcp"],
      "enabled": false
    },
    "cache": {
      "type": "stdio",
      "command": "cache-mcp",
      "args": ["--dir", "${HOME}/.cache/mcp"]
    }
  }
}
EOF
cat > "$tmp/mcp/existing.json" <<'EOF'
{
  "mcpServers": {
    "woodpecker-ci": {"command": "old"},
    "user-extra": {"command": "keep-me"}
  }
}
EOF
write_cursor_mcp "$tmp/mcp/agent.json" "$tmp/mcp/existing.json"
python3 - "$tmp/mcp/existing.json" "$HOME" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read())
home = sys.argv[2]
servers = data["mcpServers"]
assert "tmux" not in servers
assert servers["user-extra"]["command"] == "keep-me"
assert servers["woodpecker-ci"]["command"] == "woodpecker-mcp"
assert "description" not in servers["woodpecker-ci"]
assert "enabled" not in servers["woodpecker-ci"]
assert servers["cache"]["args"] == [f"--dir", f"{home}/.cache/mcp"]
PY
if write_cursor_mcp "$tmp/mcp/agent.json" "$tmp/mcp/existing.json"; then
  echo "unchanged cursor mcp was rewritten" >&2
  exit 1
fi

bash -n "$root/install.sh"
echo "cursor config tests: OK"
