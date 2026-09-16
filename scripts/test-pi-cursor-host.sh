#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
overlay="$root/common/pi/.pi/agent/patches/pi-cursor-agent/0.4.4/src"
ext="$root/common/pi/.pi/agent/extensions/cursor-host.ts"

grep -q '# Host Instructions' "$ext"
grep -q 'session_before_compact' "$ext"
grep -q 'agentFetchedRuleType(skill.description)' "$overlay/bridge/pi-context/rules-builder.ts"
grep -q 'content: skill.description' "$overlay/bridge/pi-context/rules-builder.ts"
! grep -q 'readFile' "$overlay/bridge/pi-context/rules-builder.ts"
grep -q '"edit"' "$overlay/bridge/pi-to-cursor/request-builder.ts"
grep -q 'cursor-grok-4.6-fast' "$overlay/provider/model-mapping.ts"
grep -q 'rememberCursorContextUsage' "$overlay/bridge/cursor-to-pi/executors/hook.ts"
grep -q 'applyCursorUsage(output, model)' "$overlay/provider/stream.ts"
grep -q 'shouldReuseLiveCursorSession' "$overlay/provider/stream.ts"
grep -q 'Interrupted by user message' "$overlay/provider/stream.ts"
grep -q 'HOST_INSTRUCTIONS' "$overlay/bridge/pi-context/parser.ts"
! grep -q '<available_skills>' "$ext"
grep -q 'registerCommand(skill.name' "$root/common/pi/.pi/agent/extensions/skill-slash.ts"
for skill in deep-research docs-research github-research pr-review quality-assure; do
  grep -q 'disable-model-invocation: true' "$root/common/agent/.config/agent/skills/$skill/SKILL.md"
done

DOTFILES_ROOT="$root" node --input-type=module <<'NODE'
import { pathToFileURL } from "node:url";
import { createRequire } from "node:module";

const root = process.env.DOTFILES_ROOT;
const require = createRequire(import.meta.url);

const { buildCursorHostPrompt } = await import(
  pathToFileURL(`${root}/common/pi/.pi/agent/extensions/cursor-host.ts`).href
);
const prompt = buildCursorHostPrompt({
  cwd: "/tmp/proj",
  date: "2026-09-16",
  appendSystemPrompt: "Speak Japanese.",
  contextFiles: [{ path: "/tmp/AGENTS.md", content: "Use bun." }],
  skills: [
    { name: "docs-research", description: "Read docs", filePath: "/tmp/SKILL.md" },
    { name: "d-pr", description: "Claude only", filePath: "/tmp/d-pr.md" },
  ],
});
if (!prompt.includes("# Host Instructions")) throw new Error("missing host instructions");
if (!prompt.includes("Speak Japanese.")) throw new Error("missing append system");
if (!prompt.includes("# Project Context")) throw new Error("missing project context");
if (prompt.includes("<available_skills>")) throw new Error("skill index must stay out of Cursor host prompt");
if (prompt.includes("docs-research") || prompt.includes("d-pr")) {
  throw new Error("skills leaked into Cursor host prompt");
}
if (prompt.includes("You are an AI")) throw new Error("full prompt leaked");

const { applyCursorUsage, rememberCursorContextUsage } = await import(
  pathToFileURL(`${root}/common/pi/.pi/agent/patches/pi-cursor-agent/0.4.4/src/provider/cursor-usage.ts`).href
);
const model = { contextWindow: 200000 };
const output = { usage: { input: 0, output: 400, totalTokens: 400 } };
rememberCursorContextUsage(50000, 256000);
applyCursorUsage(output, model);
if (output.usage.input !== 49600) throw new Error(`input ${output.usage.input}`);
if (output.usage.totalTokens !== 50000) throw new Error(`total ${output.usage.totalTokens}`);
if (model.contextWindow !== 256000) throw new Error(`window ${model.contextWindow}`);

const { toCanonicalId, toCursorId } = await import(
  pathToFileURL(`${root}/common/pi/.pi/agent/patches/pi-cursor-agent/0.4.4/src/provider/model-mapping.ts`).href
);
if (toCanonicalId("cursor-grok-4.6-medium-fast") !== "cursor-grok-4.6-fast") {
  throw new Error(`canonical ${toCanonicalId("cursor-grok-4.6-medium-fast")}`);
}
if (toCanonicalId("cursor-grok-4.6-high-fast") !== null) {
  throw new Error("high-fast should be hidden");
}
if (toCursorId("cursor-grok-4.6-fast", "high") !== "cursor-grok-4.6-high-fast") {
  throw new Error(toCursorId("cursor-grok-4.6-fast", "high"));
}

const { parsePiSystemPrompt } = await import(
  pathToFileURL(`${root}/common/pi/.pi/agent/patches/pi-cursor-agent/0.4.4/src/bridge/pi-context/parser.ts`).href
);
const parsed = parsePiSystemPrompt(prompt);
if (!parsed.cleanedPrompt.includes("Speak Japanese.")) throw new Error("cleaned dropped host");
if (parsed.skills.length !== 0) {
  throw new Error(JSON.stringify(parsed.skills));
}
if (parsed.contextFiles.length !== 1) throw new Error("context files missing");

const { shouldReuseLiveCursorSession } = await import(
  pathToFileURL(`${root}/common/pi/.pi/agent/patches/pi-cursor-agent/0.4.4/src/provider/live-session-policy.ts`).href
);
if (!shouldReuseLiveCursorSession([{ role: "toolResult" }])) {
  throw new Error("toolResult should reuse live session");
}
if (shouldReuseLiveCursorSession([{ role: "toolResult" }, { role: "user" }])) {
  throw new Error("user message must not reuse live session");
}
if (shouldReuseLiveCursorSession([])) {
  throw new Error("empty transcript must not reuse live session");
}

const { discoverSlashSkills, parseSkillFrontmatter } = await import(
  pathToFileURL(`${root}/common/pi/.pi/agent/extensions/skill-slash.ts`).href
);
const parsedSkill = parseSkillFrontmatter(`---
name: docs-research
description: "Read docs"
disable-model-invocation: true
---
body
`);
if (!parsedSkill.slashOnly || parsedSkill.name !== "docs-research") {
  throw new Error(JSON.stringify(parsedSkill));
}
const tmp = await import("node:fs");
const os = await import("node:os");
const path = await import("node:path");
const dir = tmp.mkdtempSync(path.join(os.tmpdir(), "pi-skills-"));
tmp.mkdirSync(path.join(dir, "docs-research"));
tmp.writeFileSync(path.join(dir, "docs-research", "SKILL.md"), `---
name: docs-research
description: Read docs
disable-model-invocation: true
---
`);
tmp.mkdirSync(path.join(dir, "github-commit"));
tmp.writeFileSync(path.join(dir, "github-commit", "SKILL.md"), `---
name: github-commit
description: Commit changes
---
`);
const slash = discoverSlashSkills([dir]);
if (slash.length !== 2) throw new Error(`slash ${slash.map((s) => s.name)}`);
if (!slash.find((s) => s.name === "docs-research")?.slashOnly) {
  throw new Error("docs-research should be slash-only");
}
if (slash.find((s) => s.name === "github-commit")?.slashOnly) {
  throw new Error("github-commit should stay auto");
}
console.log("pi-cursor-host unit checks passed");
NODE
