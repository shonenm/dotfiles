#!/bin/bash
# pi-automode は classifierModel を1つしか見ず、認証切れで fail-closed する。
# カンマ区切りの次候補へ、認証・quota 障害のときだけ倒す local patch。
set -euo pipefail

file="${PI_AUTOMODE_CLASSIFIER:-$HOME/.pi/agent/npm/node_modules/@czottmann/pi-automode/extensions/auto-mode/classifier.ts}"

node - "$file" <<'NODE'
const fs = require("node:fs");

const file = process.argv[2];
if (!fs.existsSync(file)) {
  console.error(`No pi-automode classifier found at ${file}`);
  process.exit(1);
}

const marker = "Local patch: try comma-separated classifier models";
const source = fs.readFileSync(file, "utf8");
if (source.includes(marker)) process.exit(0);

const declaration = "export const defaultClassifyAction: ClassifyAction = async (";
if (!source.includes(declaration)) {
  console.error(`No compatible pi-automode classifier found in ${file}`);
  process.exit(1);
}

const wrapper = `

function classifierInfrastructureFailed(result: ClassifyResult): boolean {
  if (result.decision !== "block") return false;
  const attempts = result.io?.attempts ?? [];
  return attempts.length === 0 || !attempts.some((attempt) => attempt.parsed);
}

// ${marker}. A parsed policy decision remains fail-closed and is never retried.
export const defaultClassifyAction: ClassifyAction = async (
  ctx,
  config,
  action,
  loadedContext,
): Promise<ClassifyResult> => {
  const candidates = config.classifierModel
    ?.split(",")
    .map((model) => model.trim())
    .filter(Boolean) ?? [];
  if (candidates.length <= 1) {
    return classifyWithSingleModel(ctx, config, action, loadedContext);
  }

  let lastResult: ClassifyResult | undefined;
  for (const classifierModel of candidates) {
    lastResult = await classifyWithSingleModel(
      ctx,
      { ...config, classifierModel },
      action,
      loadedContext,
    );
    if (!classifierInfrastructureFailed(lastResult)) return lastResult;
  }
  return lastResult!;
};
`;

fs.writeFileSync(
  file,
  source.replace(declaration, "const classifyWithSingleModel: ClassifyAction = async (") + wrapper,
);
console.log(`Patched ${file}`);
NODE
