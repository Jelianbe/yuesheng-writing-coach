/**
 * training.flow.ts 加载器单元测试
 * 验证 training-flow-mapping.json 的契约（6 类 + 5 模板 + 模板占位符）。
 */
import { describe, it, expect } from 'vitest';
import {
  FLOW_CATEGORIES,
  FLOW_TEMPLATES,
  FLOW_DEFAULT_CATEGORY,
  getFlowCategory,
} from '../training.flow';

describe('FLOW_CATEGORIES', () => {
  it('应至少包含 6 个分类（5 技法类 + _default）', () => {
    const keys = Object.keys(FLOW_CATEGORIES);
    expect(keys).toContain('开篇');
    expect(keys).toContain('人物');
    expect(keys).toContain('节奏');
    expect(keys).toContain('语言');
    expect(keys).toContain('结构');
    expect(keys).toContain('_default');
    expect(keys.length).toBeGreaterThanOrEqual(6);
  });

  it('每个分类应有 displayName + effect + abilityCategory', () => {
    for (const [key, cat] of Object.entries(FLOW_CATEGORIES)) {
      expect(cat.displayName, key).toBeTruthy();
      expect(cat.effect, key).toBeTruthy();
      expect(cat.abilityCategory, key).toBeTruthy();
    }
  });

  it('FLOW_DEFAULT_CATEGORY 应指向 _default', () => {
    expect(FLOW_DEFAULT_CATEGORY.key).toBe('_default');
  });

  it('getFlowCategory 找不到时回退默认', () => {
    const cat = getFlowCategory('不存在的分类');
    expect(cat.key).toBe('_default');
  });

  it('getFlowCategory 找得到时返回正确分类', () => {
    const cat = getFlowCategory('开篇');
    expect(cat.displayName).toBe('开篇技法');
  });
});

describe('FLOW_TEMPLATES', () => {
  it('应包含 5 个模板（stepId 1-5）', () => {
    expect(Object.keys(FLOW_TEMPLATES).length).toBe(5);
    for (const id of [1, 2, 3, 4, 5] as const) {
      expect(FLOW_TEMPLATES[id]).toBeDefined();
      expect(FLOW_TEMPLATES[id].stepId).toBe(id);
    }
  });

  it('每个模板应有 name + template + userAction + estimatedMinutes', () => {
    for (const t of Object.values(FLOW_TEMPLATES)) {
      expect(t.name).toBeTruthy();
      expect(t.template).toBeTruthy();
      expect(t.userAction).toBeTruthy();
      expect(t.estimatedMinutes).toBeGreaterThan(0);
    }
  });

  it('模板应使用 {{xxx}} 双花占位符（统一规范）', () => {
    for (const t of Object.values(FLOW_TEMPLATES)) {
      // 找出所有 {xxx} 单花形态（不应出现）
      const singleBrace = t.template.match(/(?<!\{)\{[a-zA-Z_][a-zA-Z0-9_]*\}(?!\})/g);
      expect(singleBrace ?? []).toEqual([]);
    }
  });

  it('模板占位符应在已知占位符集合内（白名单校验）', () => {
    const allowed = [
      'techniqueName',
      'description',
      'example',
      'effect',
      'constraint',
    ];
    for (const t of Object.values(FLOW_TEMPLATES)) {
      const matches = t.template.match(/\{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\}/g) ?? [];
      for (const m of matches) {
        const key = m.slice(2, -2);
        expect(allowed, `未声明占位符 ${key} in step ${t.stepId}`).toContain(key);
      }
    }
  });

  it('estimatedMinutes 顺序符合训练节奏（解<例<确认<尝试>反馈）', () => {
    const order = [1, 2, 3, 4, 5].map((id) => FLOW_TEMPLATES[id as 1 | 2 | 3 | 4 | 5].estimatedMinutes);
    // 第 4 步（尝试）应是耗时最多的
    expect(Math.max(...order)).toBe(order[3]);
  });
});
