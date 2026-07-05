/**
 * flow-mapping.loader 单测 — S25 BL-01 R-014 重构
 *
 * 验证:
 *  - JSON 加载成功(模块级单例)
 *  - 5 步模板完整且 stepId 1-5
 *  - 分类与 categoryTemplates 一一对应
 *  - 找不到分类时回退 _default
 *  - getMappingVersion 返回 1.1.0
 */

import { describe, it, expect } from 'vitest';
import {
  FLOW_CATEGORIES,
  FLOW_CATEGORY_TEMPLATES,
  FLOW_TEMPLATES,
  getFlowCategory,
  getCategoryTemplate,
  getFlowTemplate,
  getMappingVersion,
} from '../flow-mapping.loader';

describe('flow-mapping.loader — JSON 加载与索引', () => {
  it('FLOW_CATEGORIES 应包含 6 个分类(含 _default)', () => {
    expect(Object.keys(FLOW_CATEGORIES)).toHaveLength(6);
    expect(FLOW_CATEGORIES['开篇']).toBeDefined();
    expect(FLOW_CATEGORIES['人物']).toBeDefined();
    expect(FLOW_CATEGORIES['节奏']).toBeDefined();
    expect(FLOW_CATEGORIES['语言']).toBeDefined();
    expect(FLOW_CATEGORIES['结构']).toBeDefined();
    expect(FLOW_CATEGORIES['_default']).toBeDefined();
  });

  it('FLOW_TEMPLATES 应为 5 条且 stepId 1-5', () => {
    expect(FLOW_TEMPLATES[1].name).toBe('解说技法');
    expect(FLOW_TEMPLATES[2].name).toBe('例证展示');
    expect(FLOW_TEMPLATES[3].name).toBe('确认理解');
    expect(FLOW_TEMPLATES[4].name).toBe('主动尝试');
    expect(FLOW_TEMPLATES[5].name).toBe('修改反馈');
  });

  it('FLOW_CATEGORY_TEMPLATES 应与 categories 对应(5 + _default)', () => {
    expect(Object.keys(FLOW_CATEGORY_TEMPLATES)).toHaveLength(6);
    expect(FLOW_CATEGORY_TEMPLATES['开篇']?.explainTemplate).toContain('{techniqueName}');
    expect(FLOW_CATEGORY_TEMPLATES['人物']?.explainTemplate).toContain('{techniqueName}');
    expect(FLOW_CATEGORY_TEMPLATES['_default']?.explainTemplate).toContain('{techniqueName}');
  });

  it('getMappingVersion 应返回 1.1.0', () => {
    expect(getMappingVersion()).toBe('1.1.0');
  });
});

describe('flow-mapping.loader — 查找与回退', () => {
  it('getFlowCategory 已知 key 返回正确配置', () => {
    expect(getFlowCategory('开篇').abilityCategory).toBe('叙事能力');
    expect(getFlowCategory('人物').abilityCategory).toBe('角色能力');
    expect(getFlowCategory('语言').abilityCategory).toBe('语言能力');
  });

  it('getFlowCategory 未知 key 回退到 _default', () => {
    const fallback = getFlowCategory('不存在的分类');
    expect(fallback.abilityCategory).toBe('综合能力');
    expect(fallback.effect).toBe('表现效果');
  });

  it('getCategoryTemplate 已知 key 返回 5 步模板', () => {
    const tpl = getCategoryTemplate('开篇');
    expect(tpl.explainTemplate).toBeTruthy();
    expect(tpl.exampleTemplate).toBeTruthy();
    expect(tpl.verifyQuestion).toBeTruthy();
    expect(tpl.practiceTemplate).toBeTruthy();
    expect(tpl.revisionGuide).toBeTruthy();
  });

  it('getCategoryTemplate 未知 key 回退到 _default', () => {
    const fallback = getCategoryTemplate('不存在的分类');
    const defaultTpl = getCategoryTemplate('_default');
    expect(fallback).toEqual(defaultTpl);
  });

  it('getFlowTemplate 按 stepId 取模板', () => {
    expect(getFlowTemplate(1).name).toBe('解说技法');
    expect(getFlowTemplate(4).estimatedMinutes).toBe(15);
    expect(getFlowTemplate(5).estimatedMinutes).toBe(10);
  });
});
