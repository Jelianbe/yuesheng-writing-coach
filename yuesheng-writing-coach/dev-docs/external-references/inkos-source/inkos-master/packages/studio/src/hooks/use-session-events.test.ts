import { describe, expect, it } from "vitest";
import type { SSEMessage } from "./use-sse";
import { takeUnprocessedSessionMessages } from "./use-session-events";

function msg(event: string, timestamp: number, data: unknown = {}): SSEMessage {
  return { event, timestamp, data };
}

describe("takeUnprocessedSessionMessages", () => {
  it("returns every newly appended message instead of only the last one", () => {
    const seen = new WeakSet<SSEMessage>();
    const created = msg("book:created", 1, { sessionId: "s1", bookId: "b1" });
    const complete = msg("agent:complete", 2, { sessionId: "s1" });

    expect(takeUnprocessedSessionMessages([created, complete], seen)).toEqual([created, complete]);
    expect(takeUnprocessedSessionMessages([created, complete], seen)).toEqual([]);
  });

  it("still sees new events when the SSE ring buffer keeps the same length", () => {
    const seen = new WeakSet<SSEMessage>();
    const old1 = msg("agent:start", 1);
    const old2 = msg("agent:complete", 2);
    const next = msg("book:created", 3, { sessionId: "s1", bookId: "b1" });

    expect(takeUnprocessedSessionMessages([old1, old2], seen)).toEqual([old1, old2]);
    expect(takeUnprocessedSessionMessages([old2, next], seen)).toEqual([next]);
  });
});
