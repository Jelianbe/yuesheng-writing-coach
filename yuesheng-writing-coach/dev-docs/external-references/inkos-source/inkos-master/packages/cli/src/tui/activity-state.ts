import type { TuiCopy } from "./i18n.js";
import { WARM_ACCENT } from "./theme.js";

export interface ActivityState {
  readonly label: string;
  readonly frames: readonly string[];
  readonly accent: string;
  readonly intervalMs: number;
}

const DOTS = ["·  ", "·· ", "···", " ··", "  ·"] as const;

export function describeActivityState(copy: Pick<TuiCopy, "activity">): ActivityState {
  return { label: copy.activity.thinking, frames: DOTS, accent: WARM_ACCENT, intervalMs: 220 };
}
