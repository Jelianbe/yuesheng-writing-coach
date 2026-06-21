import { describe, expect, it } from "vitest"
import { buildReorderUpdates, nextChapterTitle, workTypeForProject } from "./chapters"

describe("workTypeForProject", () => {
  it("maps novel-like project types to novel works", () => {
    expect(workTypeForProject("novel")).toBe("novel")
    expect(workTypeForProject("trilogy")).toBe("novel")
    expect(workTypeForProject("series")).toBe("novel")
  })

  it("maps the remaining project types to their own work types", () => {
    expect(workTypeForProject("short_story_collection")).toBe("short_story")
    expect(workTypeForProject("graphic_novel")).toBe("graphic_novel")
    expect(workTypeForProject("screenplay")).toBe("screenplay")
  })
})

describe("nextChapterTitle", () => {
  it("numbers from one", () => {
    expect(nextChapterTitle(0)).toBe("Chapter 1")
    expect(nextChapterTitle(4)).toBe("Chapter 5")
  })
})

describe("buildReorderUpdates", () => {
  const existing = ["a", "b", "c"]

  it("assigns 1-based order following the requested sequence", () => {
    expect(buildReorderUpdates(["c", "a", "b"], existing)).toEqual([
      { id: "c", order: 1 },
      { id: "a", order: 2 },
      { id: "b", order: 3 },
    ])
  })

  it("rejects a list with missing ids", () => {
    expect(buildReorderUpdates(["a", "b"], existing)).toBeNull()
  })

  it("rejects unknown ids", () => {
    expect(buildReorderUpdates(["a", "b", "x"], existing)).toBeNull()
  })

  it("rejects duplicate ids even at the right length", () => {
    expect(buildReorderUpdates(["a", "b", "b"], existing)).toBeNull()
  })

  it("handles the empty project", () => {
    expect(buildReorderUpdates([], [])).toEqual([])
  })
})
