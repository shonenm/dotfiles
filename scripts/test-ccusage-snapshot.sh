#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/home/.claude" "$TMP_DIR/bin"
cat > "$TMP_DIR/home/.claude/ccusage.json" <<'EOF'
{"defaults":{"timezone":"Asia/Tokyo","offline":true,"mode":"auto"}}
EOF
cat > "$TMP_DIR/bin/ccusage" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo 20.0.17
  exit 0
fi
python3 - "$@" <<'PY'
import json
import sys
print(json.dumps({"args": sys.argv[1:]}))
PY
EOF
chmod +x "$TMP_DIR/bin/ccusage"

HOME="$TMP_DIR/home" XDG_STATE_HOME="$TMP_DIR/state" CCUSAGE_BIN="$TMP_DIR/bin/ccusage" \
  "$ROOT_DIR/scripts/ccusage-snapshot" 2026-06 >/dev/null

python3 - "$TMP_DIR/state/ccusage/snapshots/2026/06" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "manifest.json").read_text())
assert manifest["period"] == {
    "month": "2026-06", "since": "20260601", "until": "20260630", "timezone": "Asia/Tokyo"
}
assert manifest["ccusage"]["version"] == "20.0.17"
assert manifest["reports"]["allDaily"]["sha256"] == hashlib.sha256((root / "all-daily.json").read_bytes()).hexdigest()
assert manifest["reports"]["claudeProjects"]["sha256"] == hashlib.sha256((root / "claude-projects.json").read_bytes()).hexdigest()
assert "--all" in json.loads((root / "all-daily.json").read_text())["args"]
assert "--instances" in json.loads((root / "claude-projects.json").read_text())["args"]
PY

echo "ccusage snapshot test passed"
