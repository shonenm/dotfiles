import type { Api, AssistantMessage, Model } from "@mariozechner/pi-ai";
import type { ConversationStateStructure } from "../__generated__/agent/v1/agent_pb";

export interface CursorContextUsage {
  usedTokens: number;
  windowTokens: number;
}

let latest: CursorContextUsage | null = null;

export function rememberCursorContextUsage(
  usedTokens: number,
  windowTokens = 0,
): void {
  if (!Number.isFinite(usedTokens) || usedTokens <= 0) return;
  latest = {
    usedTokens: Math.floor(usedTokens),
    windowTokens: Math.max(0, Math.floor(windowTokens || 0)),
  };
}

export function rememberCursorTokenDetails(
  state: ConversationStateStructure | undefined,
): void {
  const details = state?.tokenDetails;
  if (!details) return;
  rememberCursorContextUsage(details.usedTokens, details.maxTokens);
}

export function applyCursorUsage(
  output: AssistantMessage,
  model?: Model<Api>,
): void {
  if (!latest) return;
  const used = latest.usedTokens;
  const outputTokens = output.usage.output || 0;
  output.usage.input = Math.max(0, used - outputTokens);
  output.usage.totalTokens = used;
  if (latest.windowTokens > 0 && model) {
    model.contextWindow = latest.windowTokens;
  }
}
