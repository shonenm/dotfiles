#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
overlay="$root/common/pi/.pi/agent/patches/pi-cursor-agent/0.4.4/src"
ext="$root/common/pi/.pi/agent/extensions/cursor-host.ts"

grep -q '# Host Instructions' "$ext"
grep -q 'session_before_compact' "$ext"
! grep -q 'agentFetched' "$overlay/bridge/pi-context/rules-builder.ts"
! grep -q 'parsed.skills' "$overlay/bridge/pi-context/rules-builder.ts"
! grep -q 'readFile' "$overlay/bridge/pi-context/rules-builder.ts"
grep -q 'rewriteSkillSlash' "$root/common/pi/.pi/agent/extensions/skill-slash.ts"
grep -q '"edit"' "$overlay/bridge/pi-to-cursor/request-builder.ts"
grep -q 'cursor-grok-4.6-fast' "$overlay/provider/model-mapping.ts"
grep -q 'rememberCursorContextUsage' "$overlay/bridge/cursor-to-pi/executors/hook.ts"
grep -q 'applyCursorUsage(output, model)' "$overlay/provider/stream.ts"
grep -q 'shouldReuseLiveCursorSession' "$overlay/provider/stream.ts"
grep -q 'Interrupted by user message' "$overlay/provider/stream.ts"
grep -q 'HOST_INSTRUCTIONS' "$overlay/bridge/pi-context/parser.ts"

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
});
if (!prompt.includes("# Host Instructions")) throw new Error("missing host instructions");
if (!prompt.includes("Speak Japanese.")) throw new Error("missing append system");
if (!prompt.includes("# Project Context")) throw new Error("missing project context");
if (!prompt.includes("/skill:name")) throw new Error("missing host skill policy");
if (prompt.includes("<available_skills>")) throw new Error("skill catalog leaked");
if (prompt.includes("You are an AI")) throw new Error("full prompt leaked");

const { rewriteSkillSlash } = await import(
  pathToFileURL(`${root}/common/pi/.pi/agent/extensions/skill-slash.ts`).href
);
if (rewriteSkillSlash("/docs-research foo", ["docs-research"], ["compact"]) !== "/skill:docs-research foo") {
  throw new Error("slash rewrite failed");
}
if (rewriteSkillSlash("/compact", ["compact"], ["compact"]) !== "/compact") {
  throw new Error("reserved slash rewritten");
}
if (rewriteSkillSlash("/skill:docs-research", ["docs-research"], []) !== "/skill:docs-research") {
  throw new Error("skill prefix rewritten");
}

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
if (parsed.skills.length !== 0) throw new Error(JSON.stringify(parsed.skills));
if (parsed.contextFiles.length !== 1) throw new Error("context files missing");
const leftover = parsePiSystemPrompt(`${prompt}\n\n<available_skills><skill><name>docs-research</name><description>Read docs</description><location>/tmp/SKILL.md</location></skill></available_skills>`);
if (leftover.skills.length !== 1 || leftover.skills[0].name !== "docs-research") {
  throw new Error(JSON.stringify(leftover.skills));
}

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
console.log("pi-cursor-host unit checks passed");
NODE
