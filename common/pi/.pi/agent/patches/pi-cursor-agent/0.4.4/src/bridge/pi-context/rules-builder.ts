/** Convert parsed Pi context into CursorRule[] for Cursor's RequestContext.rules. */

import {
  CursorRule,
  CursorRuleType,
  CursorRuleTypeGlobal,
} from "../../__generated__/agent/v1/cursor_rules_pb";
import type { ParsedPiContext } from "./parser";

function globalRule(path: string, content: string): CursorRule {
  return new CursorRule({
    fullPath: path,
    content,
    type: new CursorRuleType({
      type: { case: "global", value: new CursorRuleTypeGlobal() },
    }),
  });
}

export async function buildCursorRules(
  parsed: ParsedPiContext,
): Promise<CursorRule[]> {
  return parsed.contextFiles.map((f) => globalRule(f.path, f.content));
}
