import { describe, expect, it } from "vitest";
import type { Message, ToolExecution } from "../../types";
import { createSessionRuntime, deriveResolvedProposals, extractErrorMessage, extractToolError } from "./runtime";

function exec(overrides: Partial<ToolExecution> & { id: string; tool: string }): ToolExecution {
  const { id, tool, ...rest } = overrides;
  return {
    id,
    tool,
    label: tool,
    status: "completed",
    startedAt: 1,
    ...rest,
  };
}

describe("chat runtime error copy", () => {
  it("localizes known assistant errors", () => {
    expect(extractErrorMessage({
      message: "Latest chapter 1 is state-degraded. Repair state or rewrite that chapter before continuing.",
    })).toBe("最新第 1 章处于状态降级（state-degraded）。继续写下一章前，请先修复状态，或重写这一章。");
  });

  it("localizes known tool errors", () => {
    expect(extractToolError({
      content: [
        {
          type: "text",
          text: "Latest chapter 2 is state-degraded. Repair state or rewrite that chapter before continuing.",
        },
      ],
    })).toBe("最新第 2 章处于状态降级（state-degraded）。继续写下一章前，请先修复状态，或重写这一章。");
  });
});

describe("createSessionRuntime", () => {
  it("carries playMode on the session runtime", () => {
    const rt = createSessionRuntime({ sessionId: "s1", bookId: null, sessionKind: "play", playMode: "guided", title: null });
    expect(rt.playMode).toBe("guided");
  });
});

describe("deriveResolvedProposals", () => {
  it("marks a proposed play start as confirmed when play_start completed later", () => {
    const messages: Message[] = [
      {
        role: "assistant",
        content: "",
        timestamp: 1,
        toolExecutions: [
          exec({
            id: "proposal-1",
            tool: "propose_action",
            details: {
              kind: "proposed_action",
              action: "play_start",
              targetSessionKind: "play",
              instruction: "启动旧影院",
            },
          }),
        ],
      },
      {
        role: "assistant",
        content: "",
        timestamp: 2,
        toolExecutions: [
          exec({
            id: "play-1",
            tool: "play_start",
            details: { kind: "play_world_started" },
          }),
        ],
      },
    ];

    expect(deriveResolvedProposals(messages)).toEqual({ "proposal-1": "confirmed" });
  });

  it("marks a proposed book creation as confirmed only by an architect sub-agent", () => {
    const messages: Message[] = [
      {
        role: "assistant",
        content: "",
        timestamp: 1,
        toolExecutions: [
          exec({
            id: "proposal-1",
            tool: "propose_action",
            details: {
              kind: "proposed_action",
              action: "create_book",
              targetSessionKind: "book-create",
              instruction: "建一本债务悬疑",
            },
          }),
          exec({ id: "writer-1", tool: "sub_agent", agent: "writer" }),
          exec({ id: "architect-1", tool: "sub_agent", agent: "architect" }),
        ],
      },
    ];

    expect(deriveResolvedProposals(messages)).toEqual({ "proposal-1": "confirmed" });
  });

  it("confirms only one matching proposal per completed production action", () => {
    const messages: Message[] = [
      {
        role: "assistant",
        content: "",
        timestamp: 1,
        toolExecutions: [
          exec({
            id: "old-proposal",
            tool: "propose_action",
            details: {
              kind: "proposed_action",
              action: "play_start",
              targetSessionKind: "play",
              instruction: "启动旧广播站",
            },
          }),
          exec({
            id: "new-proposal",
            tool: "propose_action",
            details: {
              kind: "proposed_action",
              action: "play_start",
              targetSessionKind: "play",
              instruction: "启动水文站",
            },
          }),
        ],
      },
      {
        role: "assistant",
        content: "",
        timestamp: 2,
        toolExecutions: [
          exec({
            id: "play-1",
            tool: "play_start",
            details: { kind: "play_world_started" },
          }),
        ],
      },
    ];

    expect(deriveResolvedProposals(messages)).toEqual({ "new-proposal": "confirmed" });
  });
});
