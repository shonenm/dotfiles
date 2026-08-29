#!/bin/bash
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/classifier.ts" <<'TS'
export const defaultClassifyAction: ClassifyAction = async (
  ctx,
  config,
  action,
  loadedContext,
): Promise<ClassifyResult> => {
  return { decision: "allow", tier: "none", reason: "fixture" };
};
TS

PI_AUTOMODE_CLASSIFIER="$tmp/classifier.ts" "$(dirname "$0")/patch-pi-automode.sh" >/dev/null
PI_AUTOMODE_CLASSIFIER="$tmp/classifier.ts" "$(dirname "$0")/patch-pi-automode.sh" >/dev/null

[[ $(grep -c 'Local patch: try comma-separated classifier models' "$tmp/classifier.ts") == 1 ]]
grep -q 'const classifyWithSingleModel: ClassifyAction' "$tmp/classifier.ts"
grep -q 'classifierInfrastructureFailed' "$tmp/classifier.ts"
grep -q 'split(",")' "$tmp/classifier.ts"
grep -q '!attempts.some((attempt) => attempt.parsed)' "$tmp/classifier.ts"
echo "pi-automode classifier fallback patch test passed"
