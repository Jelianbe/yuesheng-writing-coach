// packages/studio/src/components/chat/play-hud/types.ts
// Shared view-model types and display constants for the play HUD's holdings UI.
// Pure data — no React, no logic — so buildView and the presentational
// components can both import without a cycle.

export interface HudDetail {
  readonly label?: string;
  readonly text: string;
}

export interface HudRow {
  readonly id: string;
  readonly glyph: string;
  readonly label: string;
  readonly value?: string;
  readonly note?: string | null;
  readonly details: ReadonlyArray<HudDetail>;
  readonly imageUrl?: string;
  // 0..1 fill for a meter bar when the slot value is numeric {current,min,max}.
  readonly ratio?: number;
  // state-slot kind (resource/pressure/timer/…), used to pick a gauge style.
  readonly kind?: string;
}

export interface HoldingRelation {
  readonly targetLabel: string;
  readonly type: string;
  readonly strength?: number;
}

export interface HoldingLifecycle {
  readonly stages: ReadonlyArray<string>;
  readonly current: string;
  readonly reason?: string;
}

// A held thing rendered as a living node: its kind, status/lifecycle, its own
// meters, the relationship web it sits in, and where it came from.
export interface HoldingRow {
  readonly id: string;
  readonly kind: string; // entity.type
  readonly glyph: string;
  readonly label: string;
  readonly imageUrl?: string;
  readonly summary?: string; // shown in inspect view
  readonly preview?: string; // one-liner for the compact slot row
  readonly statusPill?: string; // current status word (non-evidence)
  readonly lifecycle?: HoldingLifecycle; // evidence ladder
  readonly meters: ReadonlyArray<HudRow>;
  readonly relations: ReadonlyArray<HoldingRelation>;
  readonly provenanceTurn?: number;
  readonly isFresh: boolean; // entered the world on the latest turn
  readonly changeReason?: string; // why it changed this turn (non-evidence)
}

// Entity types that can be "held" (vs. people/places).
export const HOLDING_TYPES = new Set(["item", "evidence", "clue", "claim", "proof_chain"]);

export const HOLDING_GLYPH: Record<string, string> = {
  item: "🎒", evidence: "📄", clue: "🔍", claim: "💡", proof_chain: "🔗",
};

export const SLOT_GLYPH: Record<string, string> = {
  timer: "⏳", pressure: "🔥", resource: "🪙", relation: "❤", clue: "🔍", evidence: "📄", flag: "🚩",
};

export const KIND_LABEL_ZH: Record<string, string> = {
  item: "物件", evidence: "证据", clue: "线索", claim: "主张", proof_chain: "证据链",
};
export const KIND_LABEL_EN: Record<string, string> = {
  item: "Item", evidence: "Evidence", clue: "Clue", claim: "Claim", proof_chain: "Proof chain",
};

// Mirrors core PlayEvidenceStatusSchema order (packages/core/src/models/play.ts:122-131).
export const EVIDENCE_LADDER = [
  "unknown", "hinted", "seen", "collected", "verified", "weaponized", "exposed", "exhausted",
] as const;
export const LADDER_LABEL_ZH: Record<string, string> = {
  unknown: "未知", hinted: "有线索", seen: "已看见", collected: "已收集",
  verified: "已验证", weaponized: "武器化", exposed: "已揭露", exhausted: "已耗尽",
};
export const LADDER_LABEL_EN: Record<string, string> = {
  unknown: "Unknown", hinted: "Hinted", seen: "Seen", collected: "Collected",
  verified: "Verified", weaponized: "Weaponized", exposed: "Exposed", exhausted: "Exhausted",
};
