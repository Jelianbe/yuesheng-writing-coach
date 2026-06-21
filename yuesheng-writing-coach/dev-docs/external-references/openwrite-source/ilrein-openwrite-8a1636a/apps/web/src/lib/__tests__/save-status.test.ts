import { describe, expect, it } from "vitest"
import { saveStatusText } from "../save-status"

describe("saveStatusText", () => {
  const savedAt = "2026-06-09T12:34:00.000Z"

  it("reports unsaved changes while dirty", () => {
    expect(saveStatusText("dirty", savedAt)).toBe("Unsaved changes")
  })

  it("reports saving in flight", () => {
    expect(saveStatusText("saving", null)).toBe("Saving…")
  })

  it("reports failures without pretending the save happened", () => {
    expect(saveStatusText("error", savedAt)).toContain("Save failed")
  })

  it("includes the save time once saved", () => {
    expect(saveStatusText("saved", savedAt)).toMatch(/^Saved at /)
    expect(saveStatusText("saved", null)).toBe("Saved")
  })

  it("distinguishes a fresh document from a previously saved one", () => {
    expect(saveStatusText("idle", null)).toBe("Not saved yet")
    expect(saveStatusText("idle", savedAt)).toMatch(/^Last saved at /)
  })
})
