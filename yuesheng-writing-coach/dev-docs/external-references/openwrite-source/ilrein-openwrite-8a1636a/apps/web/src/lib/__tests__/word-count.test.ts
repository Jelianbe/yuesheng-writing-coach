import { describe, expect, it } from "vitest"
import { countWordsInHtml } from "../word-count"

describe("countWordsInHtml", () => {
  it("counts words in editor HTML", () => {
    expect(countWordsInHtml("<h1>Chapter One</h1><p>The dragons were restless.</p>")).toBe(6)
  })

  it("matches the server count for empty and markup-only content", () => {
    expect(countWordsInHtml("")).toBe(0)
    expect(countWordsInHtml("<p></p>")).toBe(0)
  })

  it("handles entities and repeated whitespace", () => {
    expect(countWordsInHtml("<p>one&nbsp;two   three</p>")).toBe(3)
  })
})
