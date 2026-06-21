import { describe, expect, it } from "vitest";
import {
  PlayActionIntentSchema,
  PlayActionKindSchema,
  PlayEdgeSchema,
  PlayEntitySchema,
  PlayEvidenceStatusSchema,
  PlayMutationSchema,
  PlayStateSlotSchema,
} from "../models/play.js";

describe("play models", () => {
  it("accepts only the supported human action primitives", () => {
    expect(PlayActionKindSchema.options).toEqual(["look", "say", "move", "do", "wait"]);
    expect(() => PlayActionKindSchema.parse("choose")).toThrow();
    expect(() => PlayActionKindSchema.parse("use")).toThrow();
  });

  it("accepts core world entities", () => {
    const entity = PlayEntitySchema.parse({
      id: "evidence_car_address_stats",
      type: "evidence",
      label: "车机常用地址统计",
      summary: "显示新城花园出现 187 次。",
      status: "seen",
      createdEventId: "event-0001",
      updatedEventId: "event-0001",
    });

    expect(entity.type).toBe("evidence");
    expect(entity.label).toContain("车机");

    expect(() => PlayEntitySchema.parse({
      id: "bad",
      type: "weapon",
      label: "bad",
    })).toThrow();
  });

  it("requires temporal source fields on edges", () => {
    const edge = PlayEdgeSchema.parse({
      id: "edge-supports-1",
      fromId: "evidence_car_address_stats",
      type: "supports",
      toId: "claim_husband_cohabits",
      validFromEventId: "event-0001",
      sourceEventId: "event-0001",
      visibility: { player: "seen", system: "known" },
      strength: 0.6,
      confidence: 0.8,
    });

    expect(edge.validUntilEventId).toBeNull();
    expect(edge.visibility.player).toBe("seen");

    expect(() => PlayEdgeSchema.parse({
      id: "edge-bad",
      fromId: "a",
      type: "supports",
      toId: "b",
    })).toThrow();
  });

  it("accepts generic state slots without genre-specific hard-coding", () => {
    const slot = PlayStateSlotSchema.parse({
      id: "slot_husband_suspicion",
      kind: "pressure",
      label: "丈夫警觉",
      ownerEntityId: "actor_xu_jinan",
      value: { current: 35, min: 0, max: 100 },
      updatedEventId: "event-0001",
    });

    expect(slot.kind).toBe("pressure");
    expect(slot.value).toMatchObject({ current: 35 });
  });

  it("accepts semantic time advancement without fixed ticks or genre-specific units", () => {
    const mutation = PlayMutationSchema.parse({
      eventId: "evt-2",
      turn: 2,
      actionKind: "wait",
      summary: "玩家屏息等待。",
      time: {
        duration: "几息",
        worldTime: "仍在库房门外那次停顿里",
        reason: "玩家没有离开库房，只是听门外动静。",
        worldChanges: "门外的人也停住脚步，铜匣热意更明显。",
      },
    });

    expect(mutation.timeAdvance?.elapsed).toBe("几息");
    expect(mutation.timeAdvance?.anchor).toBe("仍在库房门外那次停顿里");
    expect(mutation.timeAdvance?.rationale).toContain("库房");
    expect(mutation.timeAdvance?.synchronized).toEqual(["门外的人也停住脚步，铜匣热意更明显。"]);
  });

  it("models clue and evidence lifecycle explicitly", () => {
    expect(PlayEvidenceStatusSchema.options).toEqual([
      "unknown",
      "hinted",
      "seen",
      "collected",
      "verified",
      "weaponized",
      "exposed",
      "exhausted",
    ]);
  });

  it("accepts action intent with one primary action and secondary notes", () => {
    const intent = PlayActionIntentSchema.parse({
      actionKind: "say",
      targetEntityLabel: "徐晋安",
      intent: "逼问他刚才删了什么",
      manner: "试探但带压迫",
      risk: "提高对方警觉",
      secondaryActions: ["look: 盯着手机屏幕"],
    });

    expect(intent.actionKind).toBe("say");
    expect(intent.secondaryActions).toHaveLength(1);
  });

  it("normalizes null/empty target labels to undefined (no-target actions must not crash)", () => {
    const intent = PlayActionIntentSchema.parse({
      actionKind: "look",
      targetEntityLabel: "枪",
      targetLocationLabel: null,
      intent: "查看枪上有没有编号",
    });
    expect(intent.targetLocationLabel).toBeUndefined();
    expect(intent.targetEntityLabel).toBe("枪");

    const empty = PlayActionIntentSchema.parse({ actionKind: "wait", targetEntityLabel: "" });
    expect(empty.targetEntityLabel).toBeUndefined();
  });

  it("coerces non-string action fields, falls back on bad enums, and drops object-shaped items", () => {
    const intent = PlayActionIntentSchema.parse({
      actionKind: "investigate", // not in the enum -> falls back to "do" instead of throwing
      intent: "查看尸体",
      risk: 3,                    // number -> "3"
      ambiguity: 0,               // number -> "0"
      secondaryActions: ["看尸体", { actionKind: "look" }, 5], // object/number dropped, string kept
    });
    expect(intent.actionKind).toBe("do");
    expect(intent.risk).toBe("3");
    expect(intent.ambiguity).toBe("0");
    expect(intent.secondaryActions).toEqual(["看尸体"]);
  });

  it("accepts a mutation envelope for world changes", () => {
    const mutation = PlayMutationSchema.parse({
      eventId: "event-0002",
      turn: 2,
      actionKind: "look",
      summary: "宋词看见车机地址统计。",
      entities: {
        upsert: [{
          id: "evidence_car_address_stats",
          type: "evidence",
          label: "车机常用地址统计",
          status: "seen",
          updatedEventId: "event-0002",
        }],
      },
      edges: {
        upsert: [{
          id: "edge-evidence-supports-claim",
          fromId: "evidence_car_address_stats",
          type: "supports",
          toId: "claim_husband_cohabits",
          validFromEventId: "event-0002",
          sourceEventId: "event-0002",
          visibility: { player: "seen", husband: "unknown" },
          strength: 0.6,
        }],
      },
      stateSlots: {
        upsert: [{
          id: "slot_husband_suspicion",
          ownerEntityId: "actor_husband",
          kind: "pressure",
          label: "丈夫警觉",
          value: { current: 45, min: 0, max: 100 },
          updatedEventId: "event-0002",
        }],
      },
      evidence: {
        transitions: [{
          entityId: "evidence_car_address_stats",
          from: "unknown",
          to: "seen",
          reason: "玩家看见常用地址统计。",
        }],
      },
      notes: ["look 动作只暴露信息，不强推高潮。"],
    });

    expect(mutation.entities.upsert).toHaveLength(1);
    expect(mutation.evidence.transitions[0]?.to).toBe("seen");
  });

  it("normalizes array-shaped entities/edges and null reasons so a mutation does not crash play_step", () => {
    const mutation = PlayMutationSchema.parse({
      eventId: "evt-3",
      turn: 3,
      actionKind: "look",
      summary: null,
      entities: [{ id: "ev_x", type: "evidence", label: "线索", status: "seen", updatedEventId: "evt-3" }],
      edges: [],
      blockedReason: null,
    });
    expect(mutation.entities.upsert).toHaveLength(1);
    expect(mutation.edges.upsert).toEqual([]);
    expect(mutation.summary).toBe("");
    expect(mutation.blockedReason).toBe("");
  });

  it("drops malformed entities/edges instead of failing the whole mutation", () => {
    const mutation = PlayMutationSchema.parse({
      eventId: "evt-4",
      turn: 4,
      actionKind: "look",
      entities: [
        { id: "ent_good", type: "evidence", label: "好线索", status: "seen", updatedEventId: "evt-4" },
        { type: "evidence" }, // missing id/label — must be dropped, not crash the turn
      ],
      edges: [
        { id: "edge_good", fromId: "a", type: "supports", toId: "b", validFromEventId: "evt-4", sourceEventId: "evt-4", visibility: { player: "seen", system: "known" }, strength: 0.6, confidence: 0.8 },
        { type: "supports" }, // missing id/fromId/toId — must be dropped
      ],
    });
    expect(mutation.entities.upsert).toHaveLength(1);
    expect(mutation.entities.upsert[0]?.id).toBe("ent_good");
    expect(mutation.edges.upsert).toHaveLength(1);
    expect(mutation.edges.upsert[0]?.id).toBe("edge_good");
  });

  it("rescues relationship edges: maps alias keys (from/to/relation) and resolves label endpoints to ids (C3)", () => {
    const mutation = PlayMutationSchema.parse({
      eventId: "evt-9",
      turn: 9,
      actionKind: "say",
      entities: [
        { id: "actor_zhouye", type: "actor", label: "周野", status: "警觉", updatedEventId: "evt-9" },
        { type: "actor", label: "账房先生", status: "心虚", updatedEventId: "evt-9" }, // id backfilled
      ],
      // Model used the common alias keys + referenced endpoints by NAME, not id.
      edges: [
        { from: "周野", relation: "怀疑", to: "账房先生" },
      ],
    });
    expect(mutation.edges.upsert).toHaveLength(1);
    const edge = mutation.edges.upsert[0];
    expect(edge?.type).toBe("怀疑");
    expect(edge?.fromId).toBe("actor_zhouye");           // name -> existing id
    expect(edge?.toId).toBe("ent_账房先生");              // name -> backfilled id
    expect(edge?.validFromEventId).toBe("evt-9");         // temporal fields backfilled
  });

  it("does not collapse multiple low-information edges with the same relation type", () => {
    const mutation = PlayMutationSchema.parse({
      eventId: "evt-10",
      turn: 10,
      actionKind: "look",
      entities: [
        { id: "actor_player", type: "actor", label: "玩家", updatedEventId: "evt-10" },
        { id: "old_ticket", type: "evidence", label: "旧票", updatedEventId: "evt-10" },
        { id: "ticket_fragment", type: "evidence", label: "残片", updatedEventId: "evt-10" },
      ],
      edges: [
        { from: "玩家", relation: "持有", to: "旧票" },
        { from: "玩家", relation: "持有", to: "残片" },
      ],
    });

    expect(mutation.edges.upsert).toHaveLength(2);
    expect(new Set(mutation.edges.upsert.map((edge) => edge.id)).size).toBe(2);
    expect(mutation.edges.upsert.map((edge) => edge.toId).sort()).toEqual(["old_ticket", "ticket_fragment"]);
  });

  it("backfills edge temporal fields from the turn event id when the model omits eventId", () => {
    const mutation = PlayMutationSchema.parse({
      turn: 12,
      actionKind: "say",
      entities: [
        { id: "actor_a", type: "actor", label: "甲", updatedEventId: "evt-12" },
        { id: "actor_b", type: "actor", label: "乙", updatedEventId: "evt-12" },
      ],
      edges: [
        { from: "甲", relation: "试探", to: "乙" },
      ],
    });

    expect(mutation.eventId).toBe("evt-12");
    expect(mutation.edges.upsert[0]?.validFromEventId).toBe("evt-12");
    expect(mutation.edges.upsert[0]?.sourceEventId).toBe("evt-12");
  });

  it("backfills a missing id from the label so a labeled entity/slot survives instead of vanishing", () => {
    const mutation = PlayMutationSchema.parse({
      eventId: "evt-7",
      turn: 7,
      actionKind: "look",
      // Model wrote a complete entity/slot but forgot the boilerplate id — must be kept, not dropped.
      entities: [
        { type: "evidence", label: "半张船票", summary: "死者攥着", status: "seen", updatedEventId: "evt-7" },
      ],
      stateSlots: [
        { kind: "timer", label: "结案倒计时", value: 3, updatedEventId: "evt-7" },
      ],
    });
    expect(mutation.entities.upsert).toHaveLength(1);
    expect(mutation.entities.upsert[0]?.label).toBe("半张船票");
    expect(mutation.entities.upsert[0]?.id).toContain("ent_");
    expect(mutation.stateSlots.upsert).toHaveLength(1);
    expect(mutation.stateSlots.upsert[0]?.id).toContain("slot_");
  });

  it("never throws on a structurally-wrong mutation — every off-shape field degrades", () => {
    const mutation = PlayMutationSchema.parse({
      eventId: "evt-9",
      turn: "9",              // string number -> coerced to 9
      actionKind: "ponder",   // not in enum -> falls back to "do"
      notes: "just one note", // string -> ["just one note"]
      entities: "nope",       // garbage -> default { upsert: [] }
      blocked: "yes",         // non-boolean -> default false
    });
    expect(mutation.turn).toBe(9);
    expect(mutation.actionKind).toBe("do");
    expect(mutation.notes).toEqual(["just one note"]);
    expect(mutation.entities.upsert).toEqual([]);
    expect(mutation.blocked).toBe(false);
  });
});
