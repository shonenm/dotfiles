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
  return messages.at(-1)?.role === "toolResult";
}
