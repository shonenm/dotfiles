import { setTimeout } from "node:timers/promises";
import {
  rejectPendingExceptSession,
  rejectPendingForSession,
} from "../bridge/cursor-to-pi/tool-bridge";
import { retainOnlyAgentStore } from "../lib/agent-store";
import { evictAgentStore } from "./agent-store";
import {
  deleteLiveSession,
  getLiveSession,
  retainOnlyLiveSession,
} from "./agent-stream-hook";

const TERMINATION_WAIT_MS = 2_000;

export async function terminateSession(
  sessionId: string,
  reason: string,
  options?: { evict?: boolean },
): Promise<void> {
  const live = getLiveSession(sessionId);

  if (live) {
    live.abort(reason);
  }

  rejectPendingForSession(sessionId, reason);

  if (live) {
    await Promise.race([
      live.cursorRunPromise.catch(() => {}),
      setTimeout(TERMINATION_WAIT_MS),
    ]);
  }

  let flushed = false;
  if (live) {
    try {
      await live.flushSessionState();
      flushed = true;
    } catch {}
  }

  deleteLiveSession(sessionId);
  if (options?.evict === false) {
    return;
  }
  await evictAgentStore(sessionId, { persist: !flushed }).catch(() => {});
}

export function retainOnlyActiveSessionMemory(
  sessionId: string | null,
  reason = "Session ended",
): void {
  rejectPendingExceptSession(sessionId, reason);
  retainOnlyLiveSession(sessionId);
  retainOnlyAgentStore(sessionId);
}
