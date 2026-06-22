/**
 * SkillGraph 依赖图校验器测试
 *
 * 覆盖：
 * 1. 空 SKILL 列表
 * 2. 无依赖（合法）
 * 3. 链式依赖（合法）
 * 4. 缺失依赖
 * 5. 循环依赖
 * 6. 自依赖
 * 7. dispatcher load 时 fail-fast
 */

import { describe, it, expect } from 'vitest';
import type { Skill } from '../skill-metadata';
import { validateSkillGraph, assertSkillGraphValid } from '../skill-graph';

/** 构造测试用 Skill */
function makeSkill(id: string, depends: string[] = []): Skill {
  return {
    meta: {
      id,
      estimatedTokens: 100,
      loadWhen: {
        phases: ['P0_INIT'],
        attitudes: ['doubao'],
      },
      version: '1.0',
      depends,
    },
    content: `# ${id}`,
  };
}

describe('SkillGraph.validate', () => {
  it('空 SKILL 列表应合法', () => {
    const result = validateSkillGraph([]);
    expect(result.valid).toBe(true);
    expect(result.errors).toEqual([]);
    expect(result.cycles).toEqual([]);
    expect(result.missingDeps).toEqual([]);
  });

  it('无依赖的 SKILL 列表应合法', () => {
    const skills = [makeSkill('a'), makeSkill('b'), makeSkill('c')];
    const result = validateSkillGraph(skills);
    expect(result.valid).toBe(true);
    expect(result.cycles).toEqual([]);
    expect(result.missingDeps).toEqual([]);
  });

  it('链式依赖应合法 a→b→c', () => {
    const skills = [makeSkill('a', ['b']), makeSkill('b', ['c']), makeSkill('c')];
    const result = validateSkillGraph(skills);
    expect(result.valid).toBe(true);
    expect(result.cycles).toEqual([]);
    expect(result.missingDeps).toEqual([]);
  });

  it('缺失依赖应被检测', () => {
    const skills = [makeSkill('a', ['non-existent'])];
    const result = validateSkillGraph(skills);
    expect(result.valid).toBe(false);
    expect(result.missingDeps).toEqual([{ from: 'a', to: 'non-existent' }]);
    expect(result.errors.length).toBe(1);
    expect(result.errors[0]).toContain('"a"');
    expect(result.errors[0]).toContain('"non-existent"');
  });

  it('两节点循环依赖 a→b→a 应被检测', () => {
    const skills = [makeSkill('a', ['b']), makeSkill('b', ['a'])];
    const result = validateSkillGraph(skills);
    expect(result.valid).toBe(false);
    expect(result.cycles.length).toBeGreaterThanOrEqual(1);
    // 至少一个循环包含 a 和 b
    const hasBothNodes = result.cycles.some(c => c.includes('a') && c.includes('b'));
    expect(hasBothNodes).toBe(true);
  });

  it('三节点循环 a→b→c→a 应被检测', () => {
    const skills = [
      makeSkill('a', ['b']),
      makeSkill('b', ['c']),
      makeSkill('c', ['a']),
    ];
    const result = validateSkillGraph(skills);
    expect(result.valid).toBe(false);
    expect(result.cycles.length).toBeGreaterThanOrEqual(1);
  });

  it('自依赖应被检测（虽然 parseSkillFile 已校验，这里再测一次）', () => {
    // 注意：实际自依赖在 parseSkillFile 阶段就抛错
    // 这里测的是 validateSkillGraph 直接接收外部构造的 SKILL
    const skills = [makeSkill('a', ['a'])];
    const result = validateSkillGraph(skills);
    expect(result.valid).toBe(false);
    // 视作循环依赖
    expect(result.cycles.length + result.missingDeps.length).toBeGreaterThan(0);
  });

  it('菱形依赖 a→b, a→c, b→d, c→d 应合法', () => {
    const skills = [
      makeSkill('a', ['b', 'c']),
      makeSkill('b', ['d']),
      makeSkill('c', ['d']),
      makeSkill('d'),
    ];
    const result = validateSkillGraph(skills);
    expect(result.valid).toBe(true);
  });

  it('独立子图内的循环不影响其他子图', () => {
    // 子图 1: a → b（合法）
    // 子图 2: c → d → c（循环）
    const skills = [
      makeSkill('a', ['b']),
      makeSkill('b'),
      makeSkill('c', ['d']),
      makeSkill('d', ['c']),
    ];
    const result = validateSkillGraph(skills);
    expect(result.valid).toBe(false);
    expect(result.cycles.length).toBeGreaterThanOrEqual(1);
  });
});

describe('SkillGraph.assertSkillGraphValid', () => {
  it('合法图不抛错', () => {
    const skills = [makeSkill('a', ['b']), makeSkill('b')];
    expect(() => assertSkillGraphValid(skills)).not.toThrow();
  });

  it('循环依赖抛错（含所有错误信息）', () => {
    const skills = [makeSkill('a', ['b']), makeSkill('b', ['a'])];
    expect(() => assertSkillGraphValid(skills)).toThrow(/Circular dependency/);
  });

  it('缺失依赖抛错', () => {
    const skills = [makeSkill('a', ['missing'])];
    expect(() => assertSkillGraphValid(skills)).toThrow(/missing SKILL/);
  });
});
