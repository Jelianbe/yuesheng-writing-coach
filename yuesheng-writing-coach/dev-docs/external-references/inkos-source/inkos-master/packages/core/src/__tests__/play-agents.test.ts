import { describe, expect, it, vi } from "vitest";
import {
  PlayActionInterpreterAgent,
  PlaySceneReconcilerAgent,
  PlaySceneRendererAgent,
  PlayWorldMutatorAgent,
  buildSceneRendererSystemPrompt,
} from "../play/play-agents.js";
import { PlayMutationSchema } from "../models/play.js";

const ctx = {
  client: { provider: "openai" } as never,
  model: "test-model",
  projectRoot: "/tmp/inkos-play-test",
};

describe("play agents", () => {
  it("interprets free user text into a bounded play action", async () => {
    const agent = new PlayActionInterpreterAgent(ctx);
    vi.spyOn(agent as unknown as { chat: PlayActionInterpreterAgent["chat"] }, "chat").mockResolvedValue({
      content: JSON.stringify({
        actionKind: "look",
        targetEntityLabel: "导航记录",
        intent: "查看常用地址统计",
        manner: "不让丈夫发现",
      }),
    } as never);

    await expect(agent.interpret({
      input: "我假装看天气，顺手点开车机导航记录",
      sceneBrief: "车内，丈夫刚把东西放进后备箱。",
    })).resolves.toMatchObject({
      actionKind: "look",
      targetEntityLabel: "导航记录",
      intent: "查看常用地址统计",
    });
  });

  it("degrades invalid mutator output into a safe no-op mutation instead of throwing", async () => {
    const agent = new PlayWorldMutatorAgent(ctx);
    vi.spyOn(agent as unknown as { chat: PlayWorldMutatorAgent["chat"] }, "chat").mockResolvedValue({
      content: JSON.stringify({ eventId: "", turn: -1, actionKind: "teleport" }),
    } as never);

    // The chat agent must not hard-crash on bad model output: the bad enum falls back to "do",
    // eventId is backfilled, and the turn degrades to a no-op rather than a thrown error.
    const mutation = await agent.proposeMutation({
      turn: 1,
      input: "我打开导航",
      action: { actionKind: "look", intent: "查看导航" },
      context: "车内。",
    });
    expect(mutation.actionKind).toBe("do");
    expect(mutation.eventId).toBe("evt-1");
    expect(mutation.entities.upsert).toEqual([]);
  });

  it("uses placeholder examples in the Chinese mutator prompt instead of leaking concrete character names", async () => {
    const agent = new PlayWorldMutatorAgent(ctx);
    const chat = vi.spyOn(agent as unknown as { chat: PlayWorldMutatorAgent["chat"] }, "chat").mockResolvedValue({
      content: JSON.stringify({ eventId: "evt-1", turn: 1, actionKind: "look" }),
    } as never);

    await agent.proposeMutation({
      turn: 1,
      input: "我问老陈",
      action: { actionKind: "say", intent: "追问旧账" },
      context: "当前实体名册：actor_afu [actor]: 阿福",
      language: "zh",
    });

    const messages = chat.mock.calls[0]?.[0] as ReadonlyArray<{ readonly role: string; readonly content: string }>;
    const system = messages.find((message) => message.role === "system")?.content ?? "";
    expect(system).not.toContain("周野");
    expect(system).not.toContain("账房先生");
    expect(system).not.toContain('"status":"seen"');
    expect(system).not.toContain('"status":"collected"');
    expect(system).toContain('"status":"已发现"');
    expect(system).toContain('"status":"已收集"');
    expect(system).toContain("范例只示结构");
    expect(system).toContain("不得复用");
  });

  it("treats actor_player as the reserved player id in the Chinese mutator prompt", async () => {
    const agent = new PlayWorldMutatorAgent(ctx);
    const chat = vi.spyOn(agent as unknown as { chat: PlayWorldMutatorAgent["chat"] }, "chat").mockResolvedValue({
      content: JSON.stringify({ eventId: "evt-1", turn: 1, actionKind: "look" }),
    } as never);

    await agent.proposeMutation({
      turn: 1,
      input: "我检查背包里的车票",
      action: { actionKind: "look", intent: "检查车票" },
      context: "当前实体名册：actor_player [actor]: 临时维修员",
      language: "zh",
    });

    const messages = chat.mock.calls[0]?.[0] as ReadonlyArray<{ readonly role: string; readonly content: string }>;
    const system = messages.find((message) => message.role === "system")?.content ?? "";
    expect(system).toContain("actor_player");
    expect(system).toContain("固定保留字");
    expect(system).toContain("绝不要把它改成");
  });

  it("treats actor_player as the reserved player id in the English mutator prompt", async () => {
    const agent = new PlayWorldMutatorAgent(ctx);
    const chat = vi.spyOn(agent as unknown as { chat: PlayWorldMutatorAgent["chat"] }, "chat").mockResolvedValue({
      content: JSON.stringify({ eventId: "evt-1", turn: 1, actionKind: "look" }),
    } as never);

    await agent.proposeMutation({
      turn: 1,
      input: "I check the ticket in my bag.",
      action: { actionKind: "look", intent: "check the ticket" },
      context: "Entity roster: actor_player [actor]: night mechanic",
      language: "en",
    });

    const messages = chat.mock.calls[0]?.[0] as ReadonlyArray<{ readonly role: string; readonly content: string }>;
    const system = messages.find((message) => message.role === "system")?.content ?? "";
    expect(system).toContain("The player entity id is fixed");
    expect(system).toContain("actor_player");
    expect(system).toContain("Never rename this id");
  });

  it("does not default to numeric meters when the world contract rejects panels or stats", async () => {
    const agent = new PlayWorldMutatorAgent(ctx);
    const chat = vi.spyOn(agent as unknown as { chat: PlayWorldMutatorAgent["chat"] }, "chat").mockResolvedValue({
      content: JSON.stringify({ eventId: "evt-1", turn: 1, actionKind: "look" }),
    } as never);

    await agent.proposeMutation({
      turn: 1,
      input: "我等照片完全显影，不打开任何系统面板。",
      action: { actionKind: "wait", intent: "等待照片显影并观察细节" },
      context: [
        "世界契约（高优先级，先于题材惯例）：",
        "不要 RPG、战斗、数值或等级。证据可信度只用自然语言表达，不要游戏面板。",
      ].join("\n"),
      language: "zh",
    });

    const messages = chat.mock.calls[0]?.[0] as ReadonlyArray<{ readonly role: string; readonly content: string }>;
    const system = messages.find((message) => message.role === "system")?.content ?? "";
    expect(system).toContain("世界契约禁止数值");
    expect(system).toContain("不要输出 stateSlots");
    expect(system).toContain("自然语言状态");
  });

  it("mutator prompt keeps each player action to one adjacent beat instead of jumping ahead", async () => {
    const agent = new PlayWorldMutatorAgent(ctx);
    const chat = vi.spyOn(agent as unknown as { chat: PlayWorldMutatorAgent["chat"] }, "chat").mockResolvedValue({
      content: JSON.stringify({ eventId: "evt-1", turn: 1, actionKind: "do" }),
    } as never);

    await agent.proposeMutation({
      turn: 1,
      input: "我冲下台阶去拔那把战斧",
      action: { actionKind: "do", intent: "冲下台阶并拔起战斧" },
      context: "当前场景：敌人正在合围，战斧在庭院废墟中。",
      language: "zh",
    });

    const messages = chat.mock.calls[0]?.[0] as ReadonlyArray<{ readonly role: string; readonly content: string }>;
    const system = messages.find((message) => message.role === "system")?.content ?? "";
    expect(system).toContain("只推进相邻一拍");
    expect(system).toContain("不要替玩家越过过程");
  });

  it("renderer treats player negation and applied time as canonical", async () => {
    const prompt = buildSceneRendererSystemPrompt("open", "zh");
    expect(prompt).toContain("玩家原话里的否定动作");
    expect(prompt).toContain("没有触碰");
    expect(prompt).toContain("elapsed 和 anchor 是权威时间");
    expect(prompt).toContain("不得另写");
  });

  it("renderer bridges from the player's action instead of jumping to an epilogue", () => {
    const prompt = buildSceneRendererSystemPrompt("open", "zh");
    expect(prompt).toContain("先承接玩家动作");
    expect(prompt).toContain("不要直接跳到动作完成后");
    expect(prompt).toContain("不要写总结性尾声");
  });

  it("renders the applied state as prose plus suggested actions", async () => {
    const agent = new PlaySceneRendererAgent(ctx);
    vi.spyOn(agent as unknown as { chat: PlaySceneRendererAgent["chat"] }, "chat").mockResolvedValue({
      content: JSON.stringify({
        sceneText: "车机屏幕亮了一下，常用地址统计弹出一行冷冰冰的数字。",
        suggestedActions: ["继续翻看医院记录", "套徐晋安的话"],
      }),
    } as never);

    await expect(agent.render({
      input: "看导航",
      action: { actionKind: "look", intent: "查看导航" },
      mutationSummary: "发现新城花园 187 次。",
      stateBrief: "证据：常用地址统计=seen。",
    })).resolves.toMatchObject({
      sceneText: expect.stringContaining("车机屏幕"),
      suggestedActions: ["继续翻看医院记录", "套徐晋安的话"],
    });
  });

  it("renderer fails open: non-JSON output becomes the scene instead of throwing", async () => {
    const agent = new PlaySceneRendererAgent(ctx);
    // Model returned prose, not JSON — must degrade to using it as the scene, not crash the turn.
    vi.spyOn(agent as unknown as { chat: PlaySceneRendererAgent["chat"] }, "chat").mockResolvedValue({
      content: "雨还在下，她没有抬头，只是把书往自己那边挪了挪。",
    } as never);
    const result = await agent.render({
      input: "我看着她",
      action: { actionKind: "look", intent: "看她" },
      mutationSummary: "",
      stateBrief: "",
    });
    expect(result.sceneText).toContain("雨还在下");
    expect(result.suggestedActions).toEqual([]);
  });

  it("renderer fails open on a transient upstream error instead of crashing the turn", async () => {
    const agent = new PlaySceneRendererAgent(ctx);
    vi.spyOn(agent as unknown as { chat: PlaySceneRendererAgent["chat"] }, "chat").mockRejectedValue(
      new Error("502 Bad Gateway"),
    );
    const result = await agent.render({
      input: "我推门进去",
      action: { actionKind: "move", intent: "进门" },
      mutationSummary: "",
      stateBrief: "",
    });
    // Degraded to a placeholder scene — a thrown error here would break (and half-commit) the turn.
    expect(result.sceneText.length).toBeGreaterThan(0);
    expect(result.suggestedActions).toEqual([]);
  });

  it("reconciler extracts supplemental graph facts from rendered prose", async () => {
    const agent = new PlaySceneReconcilerAgent(ctx);
    vi.spyOn(agent as unknown as { chat: PlaySceneReconcilerAgent["chat"] }, "chat").mockResolvedValue({
      content: JSON.stringify({
        eventId: "evt-2",
        turn: 2,
        actionKind: "look",
        summary: "补记黑色U盘。",
        entities: { upsert: [{ id: "item_black_usb", type: "item", label: "黑色U盘", status: "已发现" }] },
      }),
    } as never);

    const mutation = PlayMutationSchema.parse(await agent.reconcile({
      turn: 2,
      input: "我检查抽屉",
      action: { actionKind: "look", intent: "检查抽屉" },
      mutation: { eventId: "evt-2", turn: 2, actionKind: "look", summary: "检查抽屉。" },
      sceneText: "抽屉夹层里卡着一只黑色U盘。",
      context: "当前实体名册：actor_player [actor]: 玩家",
      stateBrief: "# Play State\n- summary: 检查抽屉。\n",
      language: "zh",
    }));

    expect(mutation.entities.upsert[0]?.label).toBe("黑色U盘");
  });

  it("reconciler fails open to an empty supplement on malformed output", async () => {
    const agent = new PlaySceneReconcilerAgent(ctx);
    vi.spyOn(agent as unknown as { chat: PlaySceneReconcilerAgent["chat"] }, "chat").mockResolvedValue({
      content: "没有需要补充的内容。",
    } as never);

    const mutation = PlayMutationSchema.parse(await agent.reconcile({
      turn: 2,
      input: "我检查抽屉",
      action: { actionKind: "look", intent: "检查抽屉" },
      mutation: { eventId: "evt-2", turn: 2, actionKind: "look", summary: "检查抽屉。" },
      sceneText: "抽屉里只有灰。",
      context: "当前实体名册：actor_player [actor]: 玩家",
      stateBrief: "# Play State\n- summary: 检查抽屉。\n",
      language: "zh",
    }));

    expect(mutation.entities.upsert).toEqual([]);
    expect(mutation.edges.upsert).toEqual([]);
  });
});

describe("scene renderer prompt by mode", () => {
  it("guided 模式把选项做成可选跳板，而非每回合强制", () => {
    const prompt = buildSceneRendererSystemPrompt("guided");
    expect(prompt).toContain("0-3");
    expect(prompt).toContain("不必每回合");
    expect(prompt).toContain("不是唯一前进方式");
    expect(prompt).not.toMatch(/必须给 2-4|每回合都要给/);
  });

  it("允许'在场'回合并让世界自走、不催玩家行动", () => {
    const prompt = buildSceneRendererSystemPrompt("guided");
    expect(prompt).toContain("呼吸"); // presence is a valid, breathing turn
    expect(prompt).toContain("世界不是死的"); // world runs on its own clock
    expect(prompt).toContain("时间段"); // applied timeAdvance is rendered as world synchronization
  });

  it("renderer treats applied typed state as the source of concrete facts", () => {
    const prompt = buildSceneRendererSystemPrompt("guided");
    expect(prompt).toContain("具体的新物件");
    expect(prompt).toContain("必须先由 mutator 建成实体");
  });

  it("open 模式不强制选项数量", () => {
    const prompt = buildSceneRendererSystemPrompt("open");
    expect(prompt).not.toContain("必须给 2-4");
  });

  it("renders the scene prompt in English when language is en", () => {
    const prompt = buildSceneRendererSystemPrompt("guided", "en");
    expect(prompt).toContain("interactive-fiction scene-response author");
    expect(prompt).toContain("suggestedActions");
    expect(prompt).not.toMatch(/[一-鿿]/); // no CJK leaks into the English prompt
  });
});
