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
const { isPermissionSystemYoloEnabled, getHardDenyReason, isDefaultBranchPush } = await import(`file://${tmp}/permission-gate.ts`);
const statusline = await (await import("node:fs/promises")).readFile(`${tmp}/statusline.ts`, "utf8");

delete globalThis.__piPermissionSystem;
assert.equal(isPermissionSystemYoloEnabled(), false);
globalThis.__piPermissionSystem = { getYoloMode: () => false };
assert.equal(isPermissionSystemYoloEnabled(), false);
globalThis.__piPermissionSystem = { getYoloMode: () => true };
assert.equal(isPermissionSystemYoloEnabled(), true);
assert(statusline.includes('` THINK ${pi.getThinkingLevel()} `'));

for (const command of ["git add -A", "git add .", "git add --all", "git add -u src", "git commit -am msg", "git commit -a -m msg", "git commit --all", "cd x && git add ."]) {
  assert(getHardDenyReason(command), `should deny: ${command}`);
}
for (const command of ["git add src/a.ts", "git add -p", "git add ./src", "git add .gitignore", "git commit -m 'add -a flag'", "git commit --amend --no-edit"]) {
  assert.equal(getHardDenyReason(command), undefined, `should allow: ${command}`);
}

const { execFileSync } = await import("node:child_process");
const repo = `${tmp}/repo`;
execFileSync("git", ["init", "-q", "-b", "main", repo]);
execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@t", "-C", repo, "commit", "-q", "--allow-empty", "-m", "init"]);
assert.equal(await isDefaultBranchPush("git push", repo), true);
assert.equal(await isDefaultBranchPush("git push origin feat:main", repo), true);
assert.equal(await isDefaultBranchPush("git status", repo), false);
execFileSync("git", ["-C", repo, "switch", "-q", "-c", "feat"]);
assert.equal(await isDefaultBranchPush("git push -u origin feat", repo), false);
assert.equal(await isDefaultBranchPush("git push", repo), false);
assert.equal(await isDefaultBranchPush("git push origin main", repo), true);

console.log("OK: permission gate follows YOLO mode, blocks catch-all staging, detects default-branch push");
JS
