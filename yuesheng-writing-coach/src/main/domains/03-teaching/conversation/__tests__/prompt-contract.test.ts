/**
 * Prompt Contract 单测(Sprint 20 增量 3)
 *
 * 验证:解析器 / 校验器 / 错误结构 / 启动拦截行为
 */

import { describe, it, expect } from 'vitest';
import {
  parsePromptContract,
  validateContract,
  PromptContractError,
  type PromptContract,
} from '../prompt-contract';

const FULL_ENV = {
  availableSkills: ['core-identity', 'scenario-rules', 'teaching-strategy', 'validation-rules', 'feedback-cognition'],
  availableTechniques: ['P001', 'P002', 'P003', 'P004', 'P005', 'P006', 'P007', 'P008', 'P009', 'P010'],
  availableTools: ['chapter:read', 'diagnosis:extract', 'training:start', 'session:saveMessage'],
  availableEvents: ['chat:token', 'chat:intent', 'chat:phase_transition', 'chat:done', 'chat:error', 'diagnosis:extracted', 'training:triggered'],
};

const FULL_CONTRACT = {
  required_phases: ['trust_building', 'requirement', 'diagnosis', 'training', 'reflection'],
  required_skills: ['core-identity', 'scenario-rules', 'teaching-strategy', 'validation-rules', 'feedback-cognition'],
  required_techniques: ['P001', 'P002', 'P003', 'P004', 'P005', 'P006', 'P007', 'P008', 'P009', 'P010'],
  required_tools: ['chapter:read', 'diagnosis:extract', 'training:start', 'session:saveMessage'],
  emits_events: ['chat:token', 'chat:intent', 'chat:phase_transition', 'chat:done', 'chat:error', 'diagnosis:extracted', 'training:triggered'],
} satisfies PromptContract;

describe('parsePromptContract (增量 3)', () => {
  it('解析 V5.0.0-draft 风格的 frontmatter 数组', () => {
    const fm = `contract:
  required_phases: [trust_building, requirement, diagnosis, training, reflection]
  required_skills: [core-identity, scenario-rules]
  required_techniques: [P001, P002, P003]
  required_tools: [chapter:read, diagnosis:extract]
  emits_events: [chat:token, chat:intent]`;
    const c = parsePromptContract(fm);
    expect(c.required_phases).toHaveLength(5);
    expect(c.required_skills).toEqual(['core-identity', 'scenario-rules']);
    expect(c.required_techniques).toEqual(['P001', 'P002', 'P003']);
    expect(c.required_tools).toEqual(['chapter:read', 'diagnosis:extract']);
    expect(c.emits_events).toEqual(['chat:token', 'chat:intent']);
  });

  it('解析多行数组格式', () => {
    const fm = `contract:
  required_phases:
    - trust_building
    - requirement
    - diagnosis
  required_skills:
    - core-identity
  required_techniques:
    - P001
  required_tools:
    - chapter:read
  emits_events:
    - chat:token`;
    const c = parsePromptContract(fm);
    expect(c.required_phases).toEqual(['trust_building', 'requirement', 'diagnosis']);
    expect(c.required_skills).toEqual(['core-identity']);
  });

  it('空 category 抛错', () => {
    const fm = `contract:
  required_phases: [trust_building]
  required_skills: []
  required_techniques: [P001]
  required_tools: [t1]
  emits_events: [e1]`;
    expect(() => parsePromptContract(fm)).toThrow(/required_skills/);
  });

  it('缺 category 抛错', () => {
    const fm = `contract:
  required_phases: [trust_building]`;
    expect(() => parsePromptContract(fm)).toThrow(/required_skills/);
  });
});

describe('validateContract (增量 3)', () => {
  it('完全匹配时不抛错', () => {
    expect(() => validateContract(FULL_CONTRACT, FULL_ENV, 'v5.0.0')).not.toThrow();
  });

  it('缺失 skill → 抛 PromptContractError 含 category=skills', () => {
    const contract = { ...FULL_CONTRACT, required_skills: ['core-identity', 'NON_EXISTENT_SKILL'] };
    try {
      validateContract(contract, FULL_ENV, 'v5.0.0');
      expect.fail('应该抛错');
    } catch (err) {
      expect(err).toBeInstanceOf(PromptContractError);
      const e = err as PromptContractError;
      expect(e.contractVersion).toBe('v5.0.0');
      expect(e.mismatches.find(m => m.category === 'skills')?.missing).toContain('NON_EXISTENT_SKILL');
    }
  });

  it('缺失 technique → 抛错', () => {
    const contract = { ...FULL_CONTRACT, required_techniques: ['P001', 'P999'] };
    expect(() => validateContract(contract, FULL_ENV, 'v5.0.0')).toThrow(PromptContractError);
  });

  it('缺失 tool → 抛错', () => {
    const contract = { ...FULL_CONTRACT, required_tools: ['NON_EXISTENT_TOOL'] };
    expect(() => validateContract(contract, FULL_ENV, 'v5.0.0')).toThrow(PromptContractError);
  });

  it('缺失 event → 抛错', () => {
    const contract = { ...FULL_CONTRACT, emits_events: ['NON_EXISTENT_EVENT'] };
    expect(() => validateContract(contract, FULL_ENV, 'v5.0.0')).toThrow(PromptContractError);
  });

  it('多个 category 缺失 → 一次列出全部', () => {
    const contract = {
      ...FULL_CONTRACT,
      required_skills: ['MISSING_SKILL'],
      required_tools: ['MISSING_TOOL'],
    };
    try {
      validateContract(contract, FULL_ENV, 'v5.0.0');
      expect.fail('应该抛错');
    } catch (err) {
      const e = err as PromptContractError;
      expect(e.mismatches).toHaveLength(2);
      expect(e.mismatches.map(m => m.category).sort()).toEqual(['skills', 'tools']);
      expect(e.message).toContain('MISSING_SKILL');
      expect(e.message).toContain('MISSING_TOOL');
    }
  });

  it('错误信息包含修复指引(回滚 / 补充资源)', () => {
    const contract = { ...FULL_CONTRACT, required_skills: ['MISSING_SKILL'] };
    try {
      validateContract(contract, FULL_ENV, 'v5.0.0');
      expect.fail('应该抛错');
    } catch (err) {
      const e = err as PromptContractError;
      expect(e.message).toContain('回滚');
      expect(e.message).toContain('v5.0.0');
    }
  });
});
