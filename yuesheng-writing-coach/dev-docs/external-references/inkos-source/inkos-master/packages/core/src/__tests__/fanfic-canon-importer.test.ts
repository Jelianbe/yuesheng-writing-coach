import { describe, expect, it, vi } from "vitest";
import { FanficCanonImporter } from "../agents/fanfic-canon-importer.js";
import type { LLMClient } from "../llm/provider.js";

const TEST_CLIENT: LLMClient = {
  provider: "openai",
  apiFormat: "chat",
  stream: false,
} as unknown as LLMClient;

const ZERO_USAGE = {
  promptTokens: 0,
  completionTokens: 0,
  totalTokens: 0,
} as const;

describe("FanficCanonImporter", () => {
  it("semantically compiles long source chunks instead of truncating the tail", async () => {
    const agent = new FanficCanonImporter({
      client: TEST_CLIENT,
      model: "test-model",
      projectRoot: process.cwd(),
    });

    const chatSpy = vi.spyOn(
      agent as unknown as { chat: (...args: unknown[]) => Promise<unknown> },
      "chat",
    )
      .mockResolvedValueOnce({
        content: "片段1资料：主角甲第一次登场。",
        usage: ZERO_USAGE,
      })
      .mockResolvedValueOnce({
        content: "片段2资料：TAIL_CANON_MARKER 是尾部关键正典。",
        usage: ZERO_USAGE,
      })
      .mockResolvedValueOnce({
        content: [
          "=== SECTION: world_rules ===",
          "尾部世界规则：TAIL_CANON_MARKER。",
          "=== SECTION: character_profiles ===",
          "| 角色 | 身份 | 性格底色 | 语癖/口头禅 | 说话风格 | 行为模式 | 关键关系 | 信息边界 |",
          "|------|------|----------|-------------|----------|----------|----------|----------|",
          "| 甲 | 主角 | 克制 | （素材未提及） | 冷静 | 查证 | 无 | 只知道片段信息 |",
          "=== SECTION: key_events ===",
          "| 序号 | 事件 | 涉及角色 | 对同人写作的约束 |",
          "|------|------|----------|------------------|",
          "| 1 | 尾部事件 | 甲 | 必须保留 TAIL_CANON_MARKER |",
          "=== SECTION: power_system ===",
          "（原作无明确力量体系）",
          "=== SECTION: writing_style ===",
          "句式克制。",
        ].join("\n"),
        usage: ZERO_USAGE,
      });

    const source = `${"前段".repeat(25_000)}\nTAIL_CANON_MARKER`;
    const result = await agent.importFromText(source, "长原作", "canon");

    expect(chatSpy).toHaveBeenCalledTimes(3);
    const secondChunkMessages = chatSpy.mock.calls[1]?.[0] as Array<{ role: string; content: string }>;
    expect(secondChunkMessages[1]?.content).toContain("TAIL_CANON_MARKER");
    const finalMessages = chatSpy.mock.calls[2]?.[0] as Array<{ role: string; content: string }>;
    expect(finalMessages[1]?.content).toContain("片段2资料：TAIL_CANON_MARKER");
    expect(finalMessages[0]?.content).not.toContain("已截断");
    expect(result.worldRules).toContain("TAIL_CANON_MARKER");
  });
});
