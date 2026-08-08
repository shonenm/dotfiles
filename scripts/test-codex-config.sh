#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/codex"
sed "s|__HOME__|$tmp/home|g" "$root/templates/codex-config.toml" > "$tmp/codex/config.toml"

python3 - "$tmp/codex/config.toml" "$root/common/codex/.codex/config.toml" <<'PY'
import sys, tomllib

with open(sys.argv[1], "rb") as f:
    generated = tomllib.load(f)
with open(sys.argv[2], "rb") as f:
    fallback = tomllib.load(f)

keys = (
    "model", "model_reasoning_effort", "personality", "service_tier",
    "approval_policy", "approvals_reviewer", "default_permissions",
    "allow_login_shell", "project_doc_fallback_filenames",
    "shell_environment_policy", "features", "notice", "desktop", "plugins",
)
for key in keys:
    assert generated[key] == fallback[key], key
generated_policy = generated["permissions"]["repo-autonomous"]
fallback_policy = fallback["permissions"]["repo-autonomous"]
assert generated_policy["description"] == fallback_policy["description"]
assert generated_policy["network"] == fallback_policy["network"]
assert generated_policy["filesystem"][":minimal"] == fallback_policy["filesystem"][":minimal"]
for pattern in (".", ".git/**", "**/.env", "**/.env.*", "**/*.pem", "**/*.key", "**/*.p12", "**/*.pfx"):
    assert generated_policy["filesystem"][":workspace_roots"][pattern] == fallback_policy["filesystem"][":workspace_roots"][pattern]
PY

for skill in "$root"/common/agent/.config/agent/skills/*/SKILL.md; do
  grep -q '^name:' "$skill"
  grep -q '^description:' "$skill"
done

# Source functions without running main, then exercise every Codex skill-link branch.
HOME="$tmp/home"
# shellcheck disable=SC1091
source "$root/install.sh"
src="$tmp/source/common/agent/.config/agent/skills"
dest="$HOME/.codex/skills"
mkdir -p "$src"/{new,managed,external,plain} "$dest/plain"
ln -s "/old/common/agent/.config/agent/skills/managed" "$dest/managed"
ln -s "/external/skills/external" "$dest/external"
link_codex_skills "$src" "$dest"
[[ "$(readlink "$dest/new")" == "$src/new" ]]
[[ "$(readlink "$dest/managed")" == "$src/managed" ]]
[[ "$(readlink "$dest/external")" == "/external/skills/external" ]]
[[ -d "$dest/plain" && ! -L "$dest/plain" ]]
link_codex_skills "$src" "$dest"
[[ "$(readlink "$dest/managed")" == "$src/managed" ]]

bash -n "$root/install.sh"
if command -v codex >/dev/null; then
  CODEX_HOME="$tmp/codex" codex features list >/dev/null
  CODEX_HOME="$tmp/codex" codex --search exec --help >/dev/null
fi

echo "codex config tests: OK"
