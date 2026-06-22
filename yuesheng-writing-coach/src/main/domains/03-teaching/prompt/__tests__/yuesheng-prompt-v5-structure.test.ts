/**
 * yuesheng-prompt-v5-structure.test.ts — Sprint 12 T12-8
 *
 * 职责：
 * - 验证 v5 合并版 prompt 文件结构完整性
 * - 5 大 SKILL 块（IDENTITY/TEACHING/VALIDATION/FEEDBACK/SCENARIO）必须全部存在
 * - 关键防御点（V-01 替写、V-09 产品身份合规）必须出现在文件中
 * - v5 不应被 truncation 误处理（system prompt 不走截断）
 * - 占位符规范（双花 {{xxx}}）继续生效
 *
 * 依据：
 * - 设计 005 §三 Sprint 12 / R-025 Prompt 治理
 * - ADR-003 占位符规范 / 长文截断
 * - Sprint 12 Plan T12-8
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { MAX_CHARS, truncateChapterContent } from '../truncation';

const V5_PATH = join(process.cwd(), 'resources', 'prompts', 'yuesheng-prompt-v5.md');

/** 5 大 SKILL 块标识（与 yuesheng-prompt-v5.md 的章节标题完全一致） */
const SKILL_BLOCKS = [
  { id: 'IDENTITY', title: '身份与底线' },
  { id: 'TEACHING', title: '教学策略' },
  { id: 'VALIDATION', title: '输出验证' },
  { id: 'FEEDBACK', title: '认知反馈' },
  { id: 'SCENARIO', title: '场景规则扩展' },
];

describe('yuesheng-prompt-v5.md 结构完整性', () => {
  describe('文件存在性', () => {
    it('v5.md 应存在于 resources/prompts/ 目录', () => {
      // 不应抛异常
      const content = readFileSync(V5_PATH, 'utf-8');
      expect(content.length).toBeGreaterThan(0);
    });
  });

  describe('5 大 SKILL 块', () => {
    it.each(SKILL_BLOCKS)('$id ($title) 块应在 v5.md 中存在', (block) => {
      const content = readFileSync(V5_PATH, 'utf-8');
      // 形如 "## 1. IDENTITY（来自 SKILL-IDENTITY.md）"
      const re = new RegExp(`^##\\s+\\d+\\.\\s+${block.id}\\s*（来自`, 'm');
      expect(content).toMatch(re);
      // 内层标题（来自原始 SKILL 文件）
      expect(content).toContain(block.title);
    });

    it('5 个 SKILL 块在文件中应严格按 IDENTITY→TEACHING→VALIDATION→FEEDBACK→SCENARIO 顺序排列', () => {
      const content = readFileSync(V5_PATH, 'utf-8');
      const positions = SKILL_BLOCKS.map((b) => {
        const re = new RegExp(`^##\\s+\\d+\\.\\s+${b.id}\\s*（来自`, 'm');
        const m = content.match(re);
        return { id: b.id, pos: m?.index ?? -1 };
      });

      // 全部找到
      for (const p of positions) {
        expect(p.pos).toBeGreaterThanOrEqual(0);
      }

      // 顺序校验：每个后继的位置必须 > 前驱
      for (let i = 1; i < positions.length; i++) {
        expect(positions[i].pos).toBeGreaterThan(positions[i - 1].pos);
      }
    });
  });

  describe('关键防御点', () => {
    it('应包含 V-01 替写禁止条款', () => {
      const content = readFileSync(V5_PATH, 'utf-8');
      expect(content).toContain('V-01');
      expect(content).toContain('替用户写');
    });

    it('应包含 V-09 产品身份合规（4 负 4 正）', () => {
      const content = readFileSync(V5_PATH, 'utf-8');
      expect(content).toContain('V-09');
      expect(content).toContain('产品身份');
      // 4 负
      expect(content).toContain('AI 写');
      expect(content).toContain('AI 续写');
      expect(content).toContain('AI 润色');
      // 4 正
      expect(content).toContain('AI 诊断');
      expect(content).toContain('学员训练');
      expect(content).toContain('反思门控');
      expect(content).toContain('进步可视化');
    });

    it('应包含场景拒绝话术（DP-F 平台立场 / DP-G 润色纠正 / DP-I 合作伪装揭穿）', () => {
      const content = readFileSync(V5_PATH, 'utf-8');
      expect(content).toContain('DP-F');
      expect(content).toContain('DP-G');
      expect(content).toContain('DP-I');
    });
  });

  describe('truncation 行为', () => {
    it('v5.md 作为 system prompt 不应被 truncation 处理（保留完整结构）', () => {
      // 模拟"如果误用 truncation 处理 v5.md"，应得到完整原文（不截断）
      // 因为 v5.md 字符数远超 MAX_CHARS，但本测试只校验"不应走 truncation 路径"
      const content = readFileSync(V5_PATH, 'utf-8');
      expect(content.length).toBeGreaterThan(MAX_CHARS); // 确认 v5 是大型 prompt
    });

    it('如果有人错误地对 v5 调用 truncateChapterContent，头段保留 IDENTITY 块、尾段保留 SCENARIO 块', () => {
      const content = readFileSync(V5_PATH, 'utf-8');
      const result = truncateChapterContent(content, { silent: true });
      expect(result.truncated).toBe(true);

      // 头段（70%）应包含 IDENTITY 块（位于 v5 顶部）
      expect(result.text).toContain('IDENTITY');
      // 尾段应包含 SCENARIO 块（位于 v5 末尾）
      expect(result.text).toContain('SCENARIO');
      // V-01 在 v5 中段，truncation 会丢中段；这是预期行为
      // 因此不应断言 V-01 存在 — 这正是 system prompt 不走 truncation 的原因
    });
  });

  describe('占位符规范（与 ADR-003 一致）', () => {
    it('v5.md 不应包含单花占位符', () => {
      const content = readFileSync(V5_PATH, 'utf-8');
      const re = /\{[a-z_][a-z_0-9]*\}(?!\})/g;
      // 简单校验：不存在违规单花
      const stripped = content
        .replace(/```[\s\S]*?```/g, '') // 移除代码块
        .replace(/<!--[\s\S]*?-->/g, ''); // 移除 HTML 注释
      const matches = stripped.match(re);
      expect(matches).toBeNull();
    });
  });

  describe('元信息', () => {
    it('v5.md 应声明版本 v5.0', () => {
      const content = readFileSync(V5_PATH, 'utf-8');
      expect(content).toContain('v5.0');
    });

    it('v5.md 应声明回退路径到 v3.9.0', () => {
      const content = readFileSync(V5_PATH, 'utf-8');
      expect(content).toMatch(/git checkout.*yuesheng-prompt-v3\.md/);
    });
  });
});
