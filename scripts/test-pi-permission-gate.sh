#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ln -s "$root/common/pi/.pi/agent/extensions/permission-gate.ts" "$tmp/permission-gate.ts"
ln -s "$root/common/pi/.pi/agent/extensions/statusline.ts" "$tmp/statusline.ts"

cd "$tmp"
node --experimental-strip-types --preserve-symlinks --input-type=module - "$tmp" <<'JS'
import assert from "node:assert/strict";

const tmp = process.argv[2];
const { isPermissionSystemYoloEnabled } = await import(`file://${tmp}/permission-gate.ts`);
const statusline = await (await import("node:fs/promises")).readFile(`${tmp}/statusline.ts`, "utf8");

delete globalThis.__piPermissionSystem;
assert.equal(isPermissionSystemYoloEnabled(), false);
globalThis.__piPermissionSystem = { getYoloMode: () => false };
assert.equal(isPermissionSystemYoloEnabled(), false);
globalThis.__piPermissionSystem = { getYoloMode: () => true };
assert.equal(isPermissionSystemYoloEnabled(), true);
assert(statusline.includes('` THINK ${pi.getThinkingLevel()} `'));

console.log("OK: permission gate follows YOLO mode and statusline labels thinking level");
JS
