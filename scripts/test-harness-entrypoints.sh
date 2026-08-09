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
config = tomllib.loads((root / "common/mise/.config/mise/config.toml").read_text())
lock = tomllib.loads((root / "common/mise/.config/mise/mise.lock").read_text())
assert config["settings"]["lockfile"] is True
assert config["settings"]["minimum_release_age"] == "3d"
assert len(lock["tools"]) == len(config["tools"]) + len(tomllib.loads((root / "config/mise-linux.toml").read_text())["tools"])
for line in (root / "config/packages.npm.txt").read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#"):
        assert line.count("@") >= (2 if line.startswith("@") else 1), line
PY

echo "harness entrypoint tests: OK"
