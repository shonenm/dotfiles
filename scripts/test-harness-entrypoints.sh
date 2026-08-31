#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
help=$("$root/scripts/dots" help)
for command in apply update check doctor lock; do
  grep -q "  $command" <<< "$help"
done
if "$root/scripts/dots" unknown >/dev/null 2>&1; then
  echo "dots accepted an unknown command" >&2
  exit 1
fi

python3 - "$root" <<'PY'
import pathlib, sys, tomllib
root = pathlib.Path(sys.argv[1])
dots = (root / "scripts/dots").read_text()
update_case = dots.split("  update)\n", 1)[1].split("    ;;\n", 1)[0]
assert "git -C \"$root\" pull --ff-only" in update_case
assert "update-mise-lock" in update_case
assert "commit_mise_lock" in update_case
assert "commit --only" in dots
assert "git push" not in dots
lock_script = (root / "scripts/update-mise-lock").read_text()
assert 'XDG_CACHE_HOME="$tmp/cache"' in lock_script
assert 'MISE_LOG_LEVEL="${MISE_LOG_LEVEL:-warn}"' in lock_script
assert "Processing .*tool" in lock_script
assert "python3 -c" in lock_script
assert not any(
    line.lstrip().startswith("mise lock") and ("--quiet" in line or " -q " in line)
    for line in lock_script.splitlines()
)
config = tomllib.loads((root / "common/mise/.config/mise/config.toml").read_text())
linux = tomllib.loads((root / "config/mise-linux.toml").read_text())
lock = tomllib.loads((root / "common/mise/.config/mise/mise.lock").read_text())
assert config["settings"]["lockfile"] is True
assert config["settings"]["minimum_release_age"] == "3d"
assert len(lock["tools"]) == len(config["tools"]) + len(linux["tools"])
for tools, required in (
    (config["tools"], {"linux-x64", "linux-arm64", "macos-x64", "macos-arm64"}),
    (linux["tools"], {"linux-x64", "linux-arm64"}),
):
    for name in tools:
        entries = lock["tools"].get(name.split("[", 1)[0], [])
        assert entries, name
        platforms = {key.removeprefix("platforms.") for entry in entries for key in entry if key.startswith("platforms.")}
        backends = {entry.get("backend", "") for entry in entries}
        if not platforms and all(backend.startswith(("cargo:", "npm:")) for backend in backends):
            continue
        assert required <= platforms, (name, required - platforms)
for line in (root / "config/packages.npm.txt").read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#"):
        assert line.count("@") >= (2 if line.startswith("@") else 1), line
install = (root / "install.sh").read_text()
assert "materialize_mise_lock" in install
assert r"mise\.lock" in (root / "common/mise/.stow-local-ignore").read_text()
PY

echo "harness entrypoint tests: OK"
