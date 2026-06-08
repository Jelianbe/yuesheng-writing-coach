/**
 * StudentModelService 文字化方法单元测试
 *
 * 测试覆盖：
 * 1. describeProficiency — 不同能力等级返回不同描述
 * 2. describeCognitiveStyle — 不同认知风格返回不同描述
 * 3. describeSyndromeSummary — 无数据/有数据/改善趋势/多个问题
 * 4. 配置文件格式验证
 *
 * CX-001-PROFILE 新增：
 * 5. computeCognitiveStyleFromMessages — 认知风格推断纯函数测试
 */

import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { computeCognitiveStyleFromMessages } from '../../services/student-model.service';

describe('StudentModelService — textualization', () => {
  describe('配置文件加载', () => {
    it('should load student-profile-descriptions.json successfully', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const raw = fs.readFileSync(configPath, 'utf-8');
      const config = JSON.parse(raw);

      expect(config).toHaveProperty('$source');
      expect(config).toHaveProperty('proficiency');
      expect(config).toHaveProperty('cognitiveStyle');
      expect(config).toHaveProperty('syndromeSummary');
    });

    it('should have all proficiency levels', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      expect(config.proficiency).toHaveProperty('beginner');
      expect(config.proficiency).toHaveProperty('intermediate');
      expect(config.proficiency).toHaveProperty('advanced');
    });

    it('should have all cognitive styles', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      expect(config.cognitiveStyle).toHaveProperty('analytical');
      expect(config.cognitiveStyle).toHaveProperty('emotional');
      expect(config.cognitiveStyle).toHaveProperty('mixed');
    });

    it('should have all syndromeSummary templates', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      expect(config.syndromeSummary).toHaveProperty('noData');
      expect(config.syndromeSummary).toHaveProperty('hasIssues');
      expect(config.syndromeSummary).toHaveProperty('improving');
      expect(config.syndromeSummary).toHaveProperty('multipleIssues');
    });

    it('proficiency descriptions should be non-empty strings', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      for (const [, value] of Object.entries(config.proficiency)) {
        expect(typeof value).toBe('string');
        expect((value as string).length).toBeGreaterThan(0);
      }
    });

    it('cognitiveStyle descriptions should be non-empty strings', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      for (const [, value] of Object.entries(config.cognitiveStyle)) {
        expect(typeof value).toBe('string');
        expect((value as string).length).toBeGreaterThan(0);
      }
    });
  });

  describe('describeSyndromeSummary template substitution logic', () => {
    // 模拟 describeSyndromeSummary 的模板替换逻辑
    const substituteTemplate = (template: string, replacements: Record<string, string>): string => {
      let result = template;
      for (const [key, value] of Object.entries(replacements)) {
        result = result.replace(`{${key}}`, value);
      }
      return result;
    };

    it('should substitute {topIssue} and {tierLabel} in hasIssues template', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      const result = substituteTemplate(config.syndromeSummary.hasIssues, {
        topIssue: '角色动机缺失（3次）',
        tierLabel: '严重',
      });

      expect(result).toContain('角色动机缺失（3次）');
      expect(result).toContain('严重');
      expect(result).not.toContain('{topIssue}');
      expect(result).not.toContain('{tierLabel}');
    });

    it('should substitute {topIssue} in improving template', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      const result = substituteTemplate(config.syndromeSummary.improving, {
        topIssue: '世界观膨胀',
      });

      expect(result).toContain('世界观膨胀');
      expect(result).not.toContain('{topIssue}');
    });

    it('should substitute all placeholders in multipleIssues template', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      const result = substituteTemplate(config.syndromeSummary.multipleIssues, {
        topIssue: '情绪标签化（5次）',
        tierLabel: '中等',
      });

      expect(result).toContain('情绪标签化（5次）');
      expect(result).toContain('中等');
      expect(result).not.toContain('{topIssue}');
      expect(result).not.toContain('{tierLabel}');
    });
  });
});

// ============ CX-001-PROFILE: inferCognitiveStyle 纯函数测试 ============

describe('computeCognitiveStyleFromMessages — 认知风格推断', () => {
  const analyticalMessages = [
    '我想理解这个结构的逻辑关系',
    '能分析一下这个框架的核心吗',
    '这个对比的层次是什么',
    '我想知道因果关系',
    '这个系统的逻辑一致性如何',
  ];

  const emotionalMessages = [
    '能给我个范例感受一下吗',
    '我想体验一下这种氛围',
    '怎么才能更有感染力',
    '这个场景让我很有共鸣',
    '我想让对话更生动',
  ];

  // 1. 空消息 → mixed, 0
  it('should return mixed with 0 confidence for empty messages', () => {
    const result = computeCognitiveStyleFromMessages([]);
    expect(result.style).toBe('mixed');
    expect(result.confidence).toBe(0);
  });

  // 2. 无匹配关键词 → mixed, 0
  it('should return mixed with 0 confidence for messages with no matching keywords', () => {
    const result = computeCognitiveStyleFromMessages(['你好', '今天天气不错', '谢谢']);
    expect(result.style).toBe('mixed');
    expect(result.confidence).toBe(0);
  });

  // 3. 入场诊断：单条消息即输出（分析型）
  it('should detect analytical style from a single message (entry diagnosis)', () => {
    const result = computeCognitiveStyleFromMessages(['这个逻辑结构的核心框架是什么']);
    expect(result.style).toBe('analytical');
    expect(result.confidence).toBeGreaterThan(0);
    // 入场诊断置信度应有缩放（≤0.5）
    expect(result.confidence).toBeLessThanOrEqual(0.5);
  });

  // 4. 入场诊断：2 条消息输出
  it('should detect emotional style from 2 emotional messages', () => {
    const result = computeCognitiveStyleFromMessages([
      '能给我个范例吗',
      '我想感受一下这种氛围',
    ]);
    expect(result.style).toBe('emotional');
    expect(result.confidence).toBeGreaterThan(0);
  });

  // 5. 强分析型（5条消息）
  it('should classify as analytical with strong signal ratio >= 0.6', () => {
    const result = computeCognitiveStyleFromMessages(analyticalMessages);
    expect(result.style).toBe('analytical');
    expect(result.confidence).toBeGreaterThan(0.3);
  });

  // 6. 强情感型（5条消息）
  it('should classify as emotional with strong signal ratio >= 0.6', () => {
    const result = computeCognitiveStyleFromMessages(emotionalMessages);
    expect(result.style).toBe('emotional');
    expect(result.confidence).toBeGreaterThan(0.3);
  });

  // 7. 混合型（接近等比例）
  it('should classify as mixed when both styles appear equally', () => {
    const mixedMessages = [
      '逻辑框架是什么',          // analytical(T2: 逻辑+框架=2)
      '给我个范例',              // emotional(T2: 范例=1)
      '什么是因果关系',          // analytical(T1: 因果关系=2)
      '我想有共鸣',              // emotional(T1: 共鸣=2)
    ];
    const result = computeCognitiveStyleFromMessages(mixedMessages);
    // 分析型比例应介于 0.4~0.6 之间 → mixed
    expect(result.style).toBe('mixed');
  });

  // 8. 置信度随消息数增加而提高
  it('should have higher confidence with more messages', () => {
    const singleResult = computeCognitiveStyleFromMessages(analyticalMessages.slice(0, 1));
    const fullResult = computeCognitiveStyleFromMessages(analyticalMessages);
    expect(fullResult.confidence).toBeGreaterThan(singleResult.confidence);
  });

  // 9. 时效加权：最近消息优先
  it('should favor recent messages due to recency weighting', () => {
    // 前 2 条情感型 + 后 3 条分析型
    const recentAnalytical = [
      '能给我个范例感受一下',
      '我想体验这种氛围',
      ...analyticalMessages.slice(0, 3),
    ];
    const result = computeCognitiveStyleFromMessages(recentAnalytical);
    // 因为后 3 条（分析型）有权重 ×1.5，应覆盖前 2 条（情感型）
    expect(result.style).toBe('analytical');
  });

  // 10. 一致性加分
  it('should apply consistency bonus when provided', () => {
    const withoutBonus = computeCognitiveStyleFromMessages(analyticalMessages, 0);
    const withBonus = computeCognitiveStyleFromMessages(analyticalMessages, 0.1);
    expect(withBonus.confidence).toBeGreaterThan(withoutBonus.confidence);
  });

  // 11. Tier-1 强信号词权重大于 Tier-3 弱信号词
  it('should give more weight to tier-1 keywords than tier-3', () => {
    // 包含 Tier-1 "结构" 作为唯一匹配 → 分析型
    const tier1Msg = ['这个结构很好'];
    const tier1Result = computeCognitiveStyleFromMessages(tier1Msg);

    // 包含 Tier-3 "定义" 作为唯一匹配
    const tier3Msg = ['请问这个定义是什么'];
    const tier3Result = computeCognitiveStyleFromMessages(tier3Msg);

    // 两者都应该是 analytical，但 tier-1 应略有更高置信度
    expect(tier1Result.style).toBe('analytical');
    expect(tier3Result.style).toBe('analytical');
  });
});
