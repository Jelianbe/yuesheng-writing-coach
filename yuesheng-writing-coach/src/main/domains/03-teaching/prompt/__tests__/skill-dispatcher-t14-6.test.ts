/**
 * SkillDispatcher T14-6 测试
 *
 * 覆盖：
 * 1. 同优先级时按 estimatedTokens 升序优先（size tiebreak）
 * 2. maxCharsPerSkill content 级别截断
 * 3. maxTokens + maxCharsPerSkill 组合
 * 4. 不设置时保持向后兼容
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { SkillDispatcher } from '../skill-dispatcher';
import type { Skill } from '../skill-metadata';

const TEST_DIR = path.join(os.tmpdir(), 'test-t14-6-' + Date.now());

beforeAll(() => {
  fs.mkdirSync(TEST_DIR, { recursive: true });
});

afterAll(() => {
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
});

describe('SkillDispatcher T14-6: size tiebreak + content truncation', () => {
  it('同优先级时按 estimatedTokens 升序优先（小优先）', () => {
    const d = new SkillDispatcher();
    // 构造 3 个 SKILL：优先级都 = 5，但大小不同
    (d as unknown as { skills: Map<string, Skill> }).skills.set('big', {
      meta: { id: 'big', estimatedTokens: 800, loadWhen: { phases: ['P0_INIT'], attitudes: ['doubao'] }, tokenPriority: 5 },
      content: '# BIG',
    });
    (d as unknown as { skills: Map<string, Skill> }).skills.set('small', {
      meta: { id: 'small', estimatedTokens: 200, loadWhen: { phases: ['P0_INIT'], attitudes: ['doubao'] }, tokenPriority: 5 },
      content: '# SMALL',
    });
    (d as unknown as { skills: Map<string, Skill> }).skills.set('medium', {
      meta: { id: 'medium', estimatedTokens: 500, loadWhen: { phases: ['P0_INIT'], attitudes: ['doubao'] }, tokenPriority: 5 },
      content: '# MEDIUM',
    });
    (d as unknown as { loaded: boolean }).loaded = true;

    // maxTokens=700：应选 SMALL(200) + MEDIUM(500) = 700
    // 不应选 BIG(800)
    const result = d.selectForPhase('P0_INIT', 'doubao', { maxTokens: 700 });
    const ids = result.map(s => s.meta.id).sort();
    expect(ids).toEqual(['medium', 'small']);
  });

  it('高优先级优先于 size tiebreak', () => {
    const d = new SkillDispatcher();
    (d as unknown as { skills: Map<string, Skill> }).skills.set('p1-small', {
      meta: { id: 'p1-small', estimatedTokens: 200, loadWhen: { phases: ['P0_INIT'], attitudes: ['doubao'] }, tokenPriority: 1 },
      content: '# P1',
    });
    (d as unknown as { skills: Map<string, Skill> }).skills.set('p10-large', {
      meta: { id: 'p10-large', estimatedTokens: 900, loadWhen: { phases: ['P0_INIT'], attitudes: ['doubao'] }, tokenPriority: 10 },
      content: '# P10',
    });
    (d as unknown as { loaded: boolean }).loaded = true;

    // maxTokens=1000：应选 P10-LARGE(900) + P1-SMALL(200) = 1100? No, 1100 > 1000
    // greedy: 先 P10(900), total=900, 再 P1(200) → 1100 > 1000, skip
    // 所以仅 P10
    const result = d.selectForPhase('P0_INIT', 'doubao', { maxTokens: 1000 });
    expect(result.map(s => s.meta.id)).toEqual(['p10-large']);
  });

  it('maxCharsPerSkill: 超出阈值时截断 content', () => {
    const d = new SkillDispatcher();
    const longContent = 'a'.repeat(5000);
    (d as unknown as { skills: Map<string, Skill> }).skills.set('long-skill', {
      meta: { id: 'long-skill', estimatedTokens: 1000, loadWhen: { phases: ['P0_INIT'], attitudes: ['doubao'] } },
      content: longContent,
    });
    (d as unknown as { loaded: boolean }).loaded = true;

    const result = d.composePrompt('P0_INIT', 'doubao', { maxCharsPerSkill: 1000 });
    // 1000 字符内（包含截断标记）应远 < 5000
    expect(result.length).toBeLessThan(1500);
    expect(result.length).toBeGreaterThan(500);
  });

  it('maxCharsPerSkill: 未超出阈值时不截断', () => {
    const d = new SkillDispatcher();
    const shortContent = '# 短内容\n这只有 50 字符左右。';
    (d as unknown as { skills: Map<string, Skill> }).skills.set('short-skill', {
      meta: { id: 'short-skill', estimatedTokens: 100, loadWhen: { phases: ['P0_INIT'], attitudes: ['doubao'] } },
      content: shortContent,
    });
    (d as unknown as { loaded: boolean }).loaded = true;

    const result = d.composePrompt('P0_INIT', 'doubao', { maxCharsPerSkill: 1000 });
    expect(result).toContain('短内容');
    expect(result).not.toContain('[...'); // 没有截断标记
  });

  it('maxTokens + maxCharsPerSkill 组合：先选 SKILL 子集，再截断单 SKILL', () => {
    const d = new SkillDispatcher();
    (d as unknown as { skills: Map<string, Skill> }).skills.set('p1', {
      meta: { id: 'p1', estimatedTokens: 100, loadWhen: { phases: ['P0_INIT'], attitudes: ['doubao'] }, tokenPriority: 10 },
      content: 'a'.repeat(5000),
    });
    (d as unknown as { skills: Map<string, Skill> }).skills.set('p2', {
      meta: { id: 'p2', estimatedTokens: 100, loadWhen: { phases: ['P0_INIT'], attitudes: ['doubao'] }, tokenPriority: 5 },
      content: 'b'.repeat(5000),
    });
    (d as unknown as { loaded: boolean }).loaded = true;

    // maxTokens=200 → 选 P1+P2（按 size tiebreak 同优先级 100 优先 P1，然后 P2）
    // maxCharsPerSkill=200 → 各自截断到 200
    const result = d.composePrompt('P0_INIT', 'doubao', {
      maxTokens: 200,
      maxCharsPerSkill: 200,
    });
    expect(result).toContain('a');
    expect(result).toContain('b');
    // 总长度应远 < 10000
    expect(result.length).toBeLessThan(2000);
  });

  it('向后兼容：不传 maxCharsPerSkill 时不截断', () => {
    const d = new SkillDispatcher();
    const longContent = 'a'.repeat(5000);
    (d as unknown as { skills: Map<string, Skill> }).skills.set('long-skill', {
      meta: { id: 'long-skill', estimatedTokens: 100, loadWhen: { phases: ['P0_INIT'], attitudes: ['doubao'] } },
      content: longContent,
    });
    (d as unknown as { loaded: boolean }).loaded = true;

    const result = d.composePrompt('P0_INIT', 'doubao');
    expect(result.length).toBe(5000);
  });
});
