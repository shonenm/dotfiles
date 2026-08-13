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
if (source.includes(marker)) {
  process.exit(0);
}

const resolveNeedle = `async function resolveClassifier(
  ctx: ExtensionContext,
  config: EffectiveConfig,
): Promise<ClassifierResolution> {
  const configured = config.classifierModel;
  const model = configured
    ? (() => {
      const parsed = parseModelSpec(configured);
      return parsed
        ? ctx.modelRegistry.find(parsed.provider, parsed.id)
        : undefined;
    })()
    : ctx.model;
  if (!model) {
    return {
      reasoning: classifierReasoningForConfig(config.classifierReasoningLevel),
    };
  }

  const completionPlan = createClassifierCompletionPlan(
    model,
    config.classifierReasoningLevel,
  );
  const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
  if (!auth.ok) return { reasoning: completionPlan.reasoning };
  return {
    reasoning: completionPlan.reasoning,
    classifier: {
      model,
      apiKey: auth.apiKey,
      headers: auth.headers,
    },
    completionPlan,
  };
}`;

const resolveReplacement = `function parseClassifierModelSpecs(configured?: string): string[] {
  return configured
    ? configured.split(",").map((spec) => spec.trim()).filter(Boolean)
    : [];
}

function isClassifierInfraFailure(decision: ClassificationDecision): boolean {
  if (decision.decision !== "block" || decision.tier !== "none") return false;
  return /token is expired|API key|unauthorized|\\b401\\b|\\b403\\b|\\b429\\b|rate limit|quota|credit|authentication|error response|No classifier model/i
    .test(decision.reason);
}

async function resolveClassifierCandidates(
  ctx: ExtensionContext,
  config: EffectiveConfig,
): Promise<Array<Required<Pick<ClassifierResolution, "classifier" | "completionPlan">> & {
  reasoning: ClassifierResolution["reasoning"];
}>> {
  const specs = parseClassifierModelSpecs(config.classifierModel);
  const models = [];
  for (const spec of specs) {
    const parsed = parseModelSpec(spec);
    const found = parsed
      ? ctx.modelRegistry.find(parsed.provider, parsed.id)
      : undefined;
    if (found) models.push(found);
  }
  if (models.length === 0 && ctx.model) models.push(ctx.model);

  const resolved = [];
  for (const model of models) {
    const completionPlan = createClassifierCompletionPlan(
      model,
      config.classifierReasoningLevel,
    );
    const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
    if (!auth.ok) continue;
    resolved.push({
      reasoning: completionPlan.reasoning,
      classifier: {
        model,
        apiKey: auth.apiKey,
        headers: auth.headers,
      },
      completionPlan,
    });
  }
  return resolved;
}

async function resolveClassifier(
  ctx: ExtensionContext,
  config: EffectiveConfig,
): Promise<ClassifierResolution> {
  // ${marker} on auth/quota failure.
  const candidates = await resolveClassifierCandidates(ctx, config);
  return candidates[0] ?? {
    reasoning: classifierReasoningForConfig(config.classifierReasoningLevel),
  };
}`;

const actionNeedle = `  const resolution = await resolveClassifier(ctx, config);
  if (!resolution.classifier || !resolution.completionPlan) {
    return {
      decision: "block",
      tier: "none",
      reason: "No classifier model/API key available; auto mode fails closed.",
      reasoning: resolution.reasoning,
    };
  }
  const classifier = resolution.classifier;
  const completionPlan = resolution.completionPlan;

  const systemPrompt = buildClassifierPrompt(config);
  const transcript = buildClassifierTranscript(ctx, {
    maxUserTokens: config.maxUserTranscriptTokens,
    maxToolTokens: config.maxToolTranscriptTokens,
  });
  const contextText = \`<loaded-project-instructions>\\n\${
    loadedContext || "(none)"
  }\\n</loaded-project-instructions>\\n\\n<classifier-transcript>\\n\${
    transcript || "(none)"
  }\\n</classifier-transcript>\\n\\nLatest action to classify:\\n\${action}\`;
  const contextMessage: UserMessage = {
    role: "user",
    content: [{ type: "text", text: contextText }],
    timestamp: Date.now(),
  };

  const attempts: ClassifierIoAttempt[] = [];
  const started = Date.now();
  const decision = await classifyInStages(
    completionPlan.completeFn,
    classifier,
    { systemPrompt, contextMessage },
    ctx.signal,
    {
      sessionId: classifierCacheSessionId(ctx),
      fastClassifierMaxTokens: config.fastClassifierMaxTokens,
      reasoningLevel: completionPlan.reasoningLevel,
      onAttempt: (attempt) => attempts.push(attempt),
    },
  );

  return {
    ...decision,
    reasoning: completionPlan.reasoning,
    io: {
      model: formatModelSpec(classifier.model),
      reasoning: completionPlan.reasoning,
      prompt: {
        system: systemPrompt,
        context: contextText,
        fastInstruction: CLASSIFIER_FAST_INSTRUCTION,
        detailedInstruction: CLASSIFIER_DETAILED_INSTRUCTION,
      },
      attempts,
      durationMs: Date.now() - started,
    },
  };
};`;

const actionReplacement = `  const candidates = await resolveClassifierCandidates(ctx, config);
  if (candidates.length === 0) {
    return {
      decision: "block",
      tier: "none",
      reason: "No classifier model/API key available; auto mode fails closed.",
      reasoning: classifierReasoningForConfig(config.classifierReasoningLevel),
    };
  }

  const systemPrompt = buildClassifierPrompt(config);
  const transcript = buildClassifierTranscript(ctx, {
    maxUserTokens: config.maxUserTranscriptTokens,
    maxToolTokens: config.maxToolTranscriptTokens,
  });
  const contextText = \`<loaded-project-instructions>\\n\${
    loadedContext || "(none)"
  }\\n</loaded-project-instructions>\\n\\n<classifier-transcript>\\n\${
    transcript || "(none)"
  }\\n</classifier-transcript>\\n\\nLatest action to classify:\\n\${action}\`;
  const contextMessage: UserMessage = {
    role: "user",
    content: [{ type: "text", text: contextText }],
    timestamp: Date.now(),
  };

  const attempts: ClassifierIoAttempt[] = [];
  const started = Date.now();
  let last = candidates[0];
  let decision: ClassificationDecision | undefined;
  for (const candidate of candidates) {
    last = candidate;
    decision = await classifyInStages(
      candidate.completionPlan.completeFn,
      candidate.classifier,
      { systemPrompt, contextMessage },
      ctx.signal,
      {
        sessionId: classifierCacheSessionId(ctx),
        fastClassifierMaxTokens: config.fastClassifierMaxTokens,
        reasoningLevel: candidate.completionPlan.reasoningLevel,
        onAttempt: (attempt) => attempts.push(attempt),
      },
    );
    if (decision.decision === "allow" || !isClassifierInfraFailure(decision)) {
      last = candidate;
      break;
    }
  }

  return {
    ...decision!,
    reasoning: last.completionPlan.reasoning,
    io: {
      model: formatModelSpec(last.classifier.model),
      reasoning: last.completionPlan.reasoning,
      prompt: {
        system: systemPrompt,
        context: contextText,
        fastInstruction: CLASSIFIER_FAST_INSTRUCTION,
        detailedInstruction: CLASSIFIER_DETAILED_INSTRUCTION,
      },
      attempts,
      durationMs: Date.now() - started,
    },
  };
};`;

if (!source.includes(resolveNeedle) || !source.includes(actionNeedle)) {
  console.error(`No compatible pi-automode classifier found in ${file}`);
  process.exit(1);
}

fs.writeFileSync(
  file,
  source.replace(resolveNeedle, resolveReplacement).replace(actionNeedle, actionReplacement),
);
console.log(`Patched ${file}`);
NODE
