/** Convert parsed Pi context into CursorRule[] for Cursor's RequestContext.rules. */

import {
  CursorRule,
  CursorRuleType,
  CursorRuleTypeAgentFetched,
  CursorRuleTypeGlobal,
} from "../../__generated__/agent/v1/cursor_rules_pb";
import type { ParsedPiContext, PiSkillRef } from "./parser";

function globalRule(path: string, content: string): CursorRule {
  return new CursorRule({
    fullPath: path,
    content,
    type: new CursorRuleType({
      type: { case: "global", value: new CursorRuleTypeGlobal() },
    }),
  });
}

function agentFetchedRuleType(description: string): CursorRuleType {
  return new CursorRuleType({
    type: {
      case: "agentFetched",
      value: new CursorRuleTypeAgentFetched({ description }),
    },
  });
}

async function agentFetchedRule(skill: PiSkillRef): Promise<CursorRule> {
  return new CursorRule({
    fullPath: skill.location,
    content: skill.description,
    type: agentFetchedRuleType(skill.description),
  });
}

export async function buildCursorRules(
  parsed: ParsedPiContext,
): Promise<CursorRule[]> {
  const globals = parsed.contextFiles.map((f) => globalRule(f.path, f.content));
  const skills = await Promise.all(parsed.skills.map(agentFetchedRule));
  return [...globals, ...skills];
}
