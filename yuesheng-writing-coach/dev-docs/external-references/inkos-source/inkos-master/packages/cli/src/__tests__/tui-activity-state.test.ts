import { describe, expect, it } from "vitest";
import { describeActivityState } from "../tui/activity-state.js";
import { getTuiCopy } from "../tui/i18n.js";
import { WARM_ACCENT } from "../tui/theme.js";

describe("tui activity state", () => {
  it("uses a neutral agent thinking state", () => {
    const copy = getTuiCopy("en");
    expect(describeActivityState(copy)).toMatchObject({ label: "thinking", accent: WARM_ACCENT });
    expect(describeActivityState(copy).intervalMs).toBeGreaterThanOrEqual(180);
  });
});
