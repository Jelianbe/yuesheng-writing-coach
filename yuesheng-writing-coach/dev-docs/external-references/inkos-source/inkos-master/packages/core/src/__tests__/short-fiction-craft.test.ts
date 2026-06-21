import { describe, expect, it } from "vitest";
import { buildShortFictionWriterUserPrompt } from "../prompts/short-fiction.js";

describe("short-fiction writer craft prompt", () => {
  const prompt = buildShortFictionWriterUserPrompt({
    direction: "悬疑短篇 旧书店失踪案 反转",
    outlineMarkdown: "## 大纲\n第1章 入局",
    chapterCount: 12,
    charsPerChapter: 1000,
  });

  it("tells the writer to play out the climax as a scene, not summarize it (B3)", () => {
    expect(prompt).toContain("高潮即场景");
    expect(prompt).toContain("不要梗概"); // already-present discipline still holds
  });

  it("restrains simile over-reliance (B2)", () => {
    expect(prompt).toContain("明喻节制");
  });
});
