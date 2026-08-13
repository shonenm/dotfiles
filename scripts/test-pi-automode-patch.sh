#!/bin/bash
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/classifier.ts" <<'TS'
async function resolveClassifier(
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
}

export const defaultClassifyAction: ClassifyAction = async (
  ctx,
  config,
  action,
  loadedContext,
): Promise<ClassifyResult> => {
  const resolution = await resolveClassifier(ctx, config);
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
  const contextText = `<loaded-project-instructions>\n${
    loadedContext || "(none)"
  }\n</loaded-project-instructions>\n\n<classifier-transcript>\n${
    transcript || "(none)"
  }\n</classifier-transcript>\n\nLatest action to classify:\n${action}`;
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
};
TS

PI_AUTOMODE_CLASSIFIER="$tmp/classifier.ts" "$(dirname "$0")/patch-pi-automode.sh" >/dev/null
PI_AUTOMODE_CLASSIFIER="$tmp/classifier.ts" "$(dirname "$0")/patch-pi-automode.sh" >/dev/null

count=$(grep -c 'Local patch: try comma-separated classifier models' "$tmp/classifier.ts")
[[ "$count" == 1 ]]
grep -q 'parseClassifierModelSpecs' "$tmp/classifier.ts"
grep -q 'isClassifierInfraFailure' "$tmp/classifier.ts"
grep -q 'resolveClassifierCandidates' "$tmp/classifier.ts"
echo "pi-automode classifier fallback patch test passed"
