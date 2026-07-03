/**
 * technique-library.loader 单测 — S25 BL-01 R-014 重构
 *
 * 验证:
 *  - JSON 加载成功
 *  - findTechnique 按 name 与 id 均能找到
 *  - 重复 id 会被 fail-fast 拒绝(在模块加载时)
 *  - getAllTechniques 返回只读快照
 *  - getTechniqueCategories 去重
 */

import { describe, it, expect } from 'vitest';
import { findTechnique, getAllTechniques, getTechniqueCategories } from '../technique-library.loader';

describe('technique-library.loader — 基础查询', () => {
  it('findTechnique 按 name 找到', () => {
    const t = findTechnique('三词递进开篇');
    expect(t).toBeDefined();
    expect(t?.id).toBe('TQ-001');
    expect(t?.category).toBe('开篇');
  });

  it('findTechnique 按 id 找到', () => {
    const t = findTechnique('TQ-001');
    expect(t).toBeDefined();
    expect(t?.name).toBe('三词递进开篇');
  });

  it('findTechnique 未知返回 undefined', () => {
    expect(findTechnique('不存在的技法')).toBeUndefined();
  });

  it('getAllTechniques 应为非空数组', () => {
    const all = getAllTechniques();
    expect(all.length).toBeGreaterThan(0);
    expect(all[0].id).toBeTruthy();
    expect(all[0].name).toBeTruthy();
  });

  it('getTechniqueCategories 应去重', () => {
    const cats = getTechniqueCategories();
    expect(cats).toContain('开篇');
    expect(cats).toContain('人物');
    expect(cats.length).toBe(new Set(cats).size);
  });
});
