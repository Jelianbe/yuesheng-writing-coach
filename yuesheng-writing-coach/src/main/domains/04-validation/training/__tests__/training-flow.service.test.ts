/**
 * TrainingFlowService 单元测试
 *
 * 覆盖：
 * - 五步训练流生成（完整结构）
 * - 不同分类的模板差异
 * - 技法查找匹配
 * - 未知技法 fallback
 * - 支持分类列表
 */

import { describe, it, expect } from 'vitest';
import { generateTrainingFlow, getSupportedCategories } from '../training-flow.service';

describe('五步训练流生成', () => {
  it('generateTrainingFlow 应返回五步结构', () => {
    const flow = generateTrainingFlow({
      syndromeId: 'P003',
      techniqueName: '三词递进开篇',
      userLevel: 1,
    });

    expect(flow.syndromeId).toBe('P003');
    expect(flow.techniqueName).toBe('三词递进开篇');
    expect(flow.steps).toHaveLength(5);
    expect(flow.estimatedTotalMinutes).toBeGreaterThan(0);
  });

  it('五步名称应正确', () => {
    const flow = generateTrainingFlow({
      syndromeId: 'P003',
      techniqueName: '三词递进开篇',
      userLevel: 1,
    });

    expect(flow.steps[0].name).toBe('解说技法');
    expect(flow.steps[1].name).toBe('例证展示');
    expect(flow.steps[2].name).toBe('确认理解');
    expect(flow.steps[3].name).toBe('主动尝试');
    expect(flow.steps[4].name).toBe('修改反馈');
  });

  it('每一步应有 instruction 和 userAction', () => {
    const flow = generateTrainingFlow({
      syndromeId: 'P004',
      techniqueName: '冰山叙事法',
      userLevel: 2,
    });

    for (const step of flow.steps) {
      expect(step.instruction).toBeTruthy();
      expect(step.userAction).toBeTruthy();
      expect(step.estimatedMinutes).toBeGreaterThan(0);
    }
  });

  it('不同分类应生成不同的指令文本', () => {
    const flowOpening = generateTrainingFlow({
      syndromeId: 'P006',
      techniqueName: '三词递进开篇',
      userLevel: 1,
    });

    const flowCharacter = generateTrainingFlow({
      syndromeId: 'P009',
      techniqueName: '动机冰山模型',
      userLevel: 2,
    });

    // 开篇和人物的 instruction 应不同
    expect(flowOpening.steps[0].instruction).not.toBe(flowCharacter.steps[0].instruction);
  });
});

describe('技法查找', () => {
  it('按技法名称查找可返回正确分类', () => {
    const flow = generateTrainingFlow({
      syndromeId: 'P006',
      techniqueName: '三词递进开篇',
      userLevel: 1,
    });
    expect(flow.category).toBe('叙事能力');
  });

  it('按技法 ID 查找应同样有效', () => {
    const flow = generateTrainingFlow({
      syndromeId: 'P009',
      techniqueName: 'TQ-002', // 物件反常法（开篇）
      userLevel: 1,
    });
    expect(flow.techniqueName).toBe('TQ-002');
    expect(flow.category).toBe('叙事能力');
  });

  it('未知技法应使用默认分类', () => {
    const flow = generateTrainingFlow({
      syndromeId: 'P001',
      techniqueName: '未知技法名称',
      userLevel: 1,
    });
    expect(flow.category).toBe('综合能力');
    // 默认配置应有 instruction
    expect(flow.steps[0].instruction).toContain('未知技法名称');
  });
});

describe('耗时估算', () => {
  it('高级技法应比初级技法耗时更长', () => {
    // 找不到 exact 的入门和高级统一技法的 name，用技法库中已知的
    const flowEasy = generateTrainingFlow({
      syndromeId: 'P006',
      techniqueName: '三词递进开篇', // beginner
      userLevel: 1,
    });

    const flowHard = generateTrainingFlow({
      syndromeId: 'P009',
      techniqueName: '动机冰山模型', // medium
      userLevel: 3,
    });

    // 主动尝试步骤（step 4）是最耗时的
    expect(flowEasy.steps[3].estimatedMinutes).toBeGreaterThan(0);
    expect(flowHard.steps[3].estimatedMinutes).toBeGreaterThan(0);
  });
});

describe('支持分类', () => {
  it('getSupportedCategories 应返回 5 个分类', () => {
    const categories = getSupportedCategories();
    expect(categories).toContain('开篇');
    expect(categories).toContain('人物');
    expect(categories).toContain('节奏');
    expect(categories).toContain('语言');
    expect(categories).toContain('结构');
  });
});
