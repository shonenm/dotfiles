/** Cursor live sessions may be reused only to return tool results. */
export function shouldReplaceCachedTurns(
  cachedTurnCount: number,
  rebuiltTurnCount: number,
): boolean {
  return rebuiltTurnCount > cachedTurnCount;
}

export function shouldReuseLiveCursorSession(
  messages: ReadonlyArray<{ role?: string } | undefined>,
): boolean {
  if (messages.at(-1)?.role !== "toolResult") return false;
  for (let index = messages.length - 2; index >= 0; index--) {
    const role = messages[index]?.role;
    if (role === "system") return false;
    if (role === "assistant") break;
  }
  return true;
}
