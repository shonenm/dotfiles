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
grep -q 'cursor-grok-4.6-fast' "$overlay/provider/model-mapping.ts"
grep -q 'rememberCursorContextUsage' "$overlay/bridge/cursor-to-pi/executors/hook.ts"
grep -q 'applyCursorUsage(output, model)' "$overlay/provider/stream.ts"
grep -q 'shouldReuseLiveCursorSession' "$overlay/provider/stream.ts"
grep -q 'shouldReplaceCachedTurns' "$overlay/bridge/pi-to-cursor/request-builder.ts"
grep -q 'evict: false' "$overlay/provider/stream.ts"
grep -q 'restoreAgentStoreFromBranch' "$overlay/provider/stream.ts"
grep -q 'options?: { evict?: boolean }' "$overlay/provider/session-lifecycle.ts"
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

const { shouldReplaceCachedTurns } = await import(
  pathToFileURL(`${root}/common/pi/.pi/agent/patches/pi-cursor-agent/0.4.4/src/provider/live-session-policy.ts`).href
);
if (!shouldReplaceCachedTurns(0, 2)) throw new Error("empty cache must take rebuilt turns");
if (shouldReplaceCachedTurns(3, 1)) throw new Error("shorter rebuild must not replace cache");
console.log("pi-cursor-host unit checks passed");
NODE

(
  pi_package="$(npm root -g)/@earendil-works/pi-coding-agent"
  pkg_dir="${PI_CURSOR_AGENT_DIR:-$HOME/.pi/agent/npm/node_modules/pi-cursor-agent}"
  mkdir -p "$root/tmp"
  tmp=$(mktemp -d "$root/tmp/pi-cursor-transcript.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/package" "$tmp/project"
  cp -R "$pkg_dir/src" "$tmp/package/"
  cp "$pkg_dir/package.json" "$tmp/package/"
  ln -s "$(dirname "$pkg_dir")" "$tmp/node_modules"
  PI_CURSOR_AGENT_DIR="$tmp/package" "$root/scripts/patch-pi-cursor-agent.sh"
  node --input-type=module - "$pi_package" "$tmp" <<'JS'
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
const [piPackage, tmp] = process.argv.slice(2);
const { loadExtensions } = await import(pathToFileURL(join(piPackage, "dist/core/extensions/loader.js")).href);
const probe = join(tmp, "probe.ts");
await writeFile(probe, `
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { Type } from "typebox";
import { Value } from "@bufbuild/protobuf";
import { normalizeContext, getCurrentSystemPrompt } from "@earendil-works/pi-ai";
import { createEditTool } from "@earendil-works/pi-coding-agent";
import { getContextTools, buildRunRequest } from "${tmp}/package/src/bridge/pi-to-cursor/request-builder.ts";
import { shouldReuseLiveCursorSession } from "${tmp}/package/src/provider/live-session-policy.ts";
import { LocalMcpExecutor } from "${tmp}/package/src/bridge/cursor-to-pi/executors/mcp.ts";
import { resolveToolResult } from "${tmp}/package/src/bridge/cursor-to-pi/tool-bridge.ts";
export default function(pi) {
 pi.registerTool({name:"cursor_transcript_probe",label:"Probe",description:"Offline transcript regression",parameters:Type.Object({}),async execute(){
  const edits=Type.Object({path:Type.String(),edits:Type.Array(Type.Object({oldText:Type.String(),newText:Type.String()}))});
  const tool=(name,parameters=Type.Object({}))=>({name,description:name,parameters});
  const system={role:"system",content:"",sections:{rules:"<rules>Use edit for precise changes. Use write only for new files or complete rewrites.</rules>",project_context:"<project_context>Preserve unrelated files.</project_context>"},toolsAdded:[tool("read"),tool("bash"),tool("write"),tool("edit",edits),tool("find"),tool("custom_tool")],timestamp:0};
  const user={role:"user",content:"Edit only the requested value.",timestamp:1};
  const context=normalizeContext({messages:[system,user]});
  assert.deepEqual(Object.keys(context),["messages"]);
  const tools=getContextTools(context);
  assert.deepEqual(tools.map(t=>t.name),["edit","find","custom_tool"]);
  const edit=tools.find(t=>t.name==="edit");
  assert.deepEqual(Value.fromBinary(edit.inputSchema).toJson(),JSON.parse(JSON.stringify(edits)));
  const blobs=new Map();
  const blobStore={setBlob:(_ctx,id,bytes)=>{blobs.set(Buffer.from(id).toString("hex"),bytes);return Promise.resolve();}};
  const model={api:"cursor-agent",id:"composer-2.5",name:"Composer 2.5"};
  const build=(context,conversationState)=>buildRunRequest({model,context,conversationState,conversationId:"offline",blobStore,mcpToolDefinitions:getContextTools(context)});
  const root=(state)=>JSON.parse(new TextDecoder().decode(blobs.get(Buffer.from(state.rootPromptMessagesJson[0]).toString("hex")))).content;
  const first=build(context);
  assert.equal(root(first.conversationState),getCurrentSystemPrompt(context.messages));
  assert(root(first.conversationState).includes("Preserve unrelated files."));
  assert(root(first.conversationState).includes("Use edit for precise changes."));
  assert.deepEqual(first.initialRequest.message.value.mcpTools.mcpTools.map(t=>t.name),["edit","find","custom_tool"]);
  const assistant={role:"assistant",content:[],timestamp:2};
  const toolResult={role:"toolResult",toolName:"edit",toolCallId:"fixture",content:[],timestamp:3};
  assert(shouldReuseLiveCursorSession([system,user,assistant,toolResult]));
  const delta={role:"system",content:"",sections:{rules:"<rules>Updated rules.</rules>"},toolsRemoved:[{name:"custom_tool"}],toolsAdded:[tool("replacement_tool")],timestamp:4};
  assert(!shouldReuseLiveCursorSession([system,user,assistant,delta,toolResult]));
  const resumed=normalizeContext({messages:[system,user,assistant,toolResult,delta,{...user,timestamp:5}]});
  const second=build(resumed,first.conversationState);
  assert.equal(root(second.conversationState),getCurrentSystemPrompt(resumed.messages));
  assert(root(second.conversationState).includes("Updated rules."));
  assert(!root(second.conversationState).includes("Use edit for precise changes."));
  assert.deepEqual(getContextTools(resumed).map(t=>t.name),["edit","find","replacement_tool"]);
  const fixture="${tmp}/project/fixture.ts";
  const original="export const stable = 1;\\nexport const change = 2;\\nexport const untouched = 3;\\n";
  await writeFile(fixture,original);
  let denied=false;
  let executions=0;
  const channel={sessionId:"offline",push(event){
   const request=event.request;
   assert.equal(request.piToolName,"edit");
   executions++;
   const promise=denied?Promise.resolve({content:[{type:"text",text:"Scoped write denied"}],isError:true}):createEditTool("${tmp}/project").execute(request.toolCallId,request.piToolArgs);
   promise.then(result=>resolveToolResult({role:"toolResult",toolName:"edit",toolCallId:request.toolCallId,...result,timestamp:0})).catch(error=>resolveToolResult({role:"toolResult",toolName:"edit",toolCallId:request.toolCallId,content:[{type:"text",text:error.message}],isError:true,timestamp:0}));
  }};
  const executor=new LocalMcpExecutor({cwd:"${tmp}/project",getActiveTools:()=>new Set(tools.map(t=>t.name)),getCtx:()=>null,getChannel:()=>channel});
  const args={toolName:"edit",toolCallId:"fixture-edit",args:Object.fromEntries(Object.entries({path:fixture,edits:[{oldText:"change = 2",newText:"change = 4"}]}).map(([key,value])=>[key,Value.fromJson(value).toBinary()]))};
  const success=await executor.execute(null,args);
  assert.equal(success.result.case,"success");
  assert(!success.result.value.isError);
  const changed=original.replace("change = 2","change = 4");
  assert.equal(await readFile(fixture,"utf8"),changed);
  denied=true;
  const rejected=await executor.execute(null,{...args,toolCallId:"fixture-denied"});
  assert.equal(rejected.result.value.isError,true);
  assert.equal(await readFile(fixture,"utf8"),changed);
  const missing=await executor.execute(null,{...args,toolName:"write",toolCallId:"fixture-unavailable"});
  assert.equal(missing.result.case,"toolNotFound");
  assert.equal(executions,2);
  return {content:[],details:{passed:true}};
 }});
}
`);
const loaded = await loadExtensions([probe, join(tmp, "package/src/index.ts")], join(tmp, "project"));
assert.deepEqual(loaded.errors, []);
const definition = loaded.extensions[0].tools.get("cursor_transcript_probe").definition;
const result = await definition.execute("offline", {}, undefined, undefined, {cwd:join(tmp,"project")});
assert.deepEqual(result.details, {passed:true});
const stream = await readFile(join(tmp, "package/src/provider/stream.ts"), "utf8");
assert(!stream.includes("preparePiContext"));
assert(!stream.includes("context.systemPrompt"));
assert(!stream.includes("systemPromptOverride"));
console.log("pi-cursor transcript, cached prompt, system delta, native edit and rejection checks passed (no network/model calls)");
JS
)
