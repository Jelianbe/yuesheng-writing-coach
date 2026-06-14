import { describe, it, expect } from 'vitest';
import {
  validateOutput,
  hasFatalViolations,
  summarizeViolations,
  type RulesConfig,
} from './output-validator';

const mockRulesConfig: RulesConfig = {
  version: '1.0',
  updatedAt: '2026-06-14',
  description: '测试用规则配置',
  rules: [
    {
      id: 'V-01',
      level: 'fatal',
      description: '禁止替用户写完整句子或段落',
      detectPattern: { type: 'keyword', patterns: ['你可以改为', '建议你改为'] },
      applicableRoles: ['teacher', 'assistant', 'clown'],
      examples: { bad: ['你可以改为：在第三章开头加入一段描写'], good: ['你觉得如果从主角视角切入会怎样？'] },
      testCases: [
        { input: '你可以改为：在第三章开头加入一段描写', expected: 'fail', matchedRules: ['V-01'] },
        { input: '你觉得如果从主角视角切入会怎样？', expected: 'pass' },
      ],
    },
    {
      id: 'V-02',
      level: 'fatal',
      description: '禁止替用户做决定',
      detectPattern: { type: 'keyword', patterns: ['你应该', '你务必', '你最好'] },
      applicableRoles: ['teacher', 'assistant', 'clown'],
      examples: { bad: ['你应该选择第一人称'], good: ['这里有两个方向可以考虑'] },
      testCases: [
        { input: '你应该选择第一人称来写', expected: 'fail', matchedRules: ['V-02'] },
        { input: '这里有两个方向可以考虑', expected: 'pass' },
      ],
    },
    {
      id: 'V-03',
      level: 'warning',
      description: '禁止暴露内部编号',
      detectPattern: { type: 'keyword', patterns: ['P001', 'A003'] },
      applicableRoles: ['teacher', 'assistant', 'clown'],
      examples: { bad: ['检测到 P001 说明书症候'], good: ['我注意到你在用大量说明来交代背景'] },
      testCases: [
        { input: '检测到 P001 说明书症候，建议执行 A003', expected: 'fail', matchedRules: ['V-03'] },
        { input: '我注意到你在用大量说明来交代背景', expected: 'pass' },
      ],
    },
    {
      id: 'V-04',
      level: 'suggestion',
      description: '引用格式规范',
      detectPattern: { type: 'regex', patterns: ['\\[\\[chapter:[^\\]]+\\]\\]'] },
      applicableRoles: ['teacher', 'assistant'],
      examples: { bad: ['你在第三章开头写了'], good: ['在 [[chapter:第三章]] 中'] },
      testCases: [
        { input: '引用章节时不使用正确格式', expected: 'fail' },
        { input: '在 [[chapter:第三章]] 中你用了大量说明', expected: 'pass' },
      ],
    },
  ],
};

describe('output-validator', () => {
  describe('validateOutput', () => {
    it('应检测 V-01 违规（禁止替写）', () => {
      const results = validateOutput('你可以改为：在第三章开头加入一段描写', mockRulesConfig);
      const v01 = results.find(r => r.ruleId === 'V-01');
      expect(v01).toBeDefined();
      expect(v01!.passed).toBe(false);
      expect(v01!.matchedPatterns).toContain('你可以改为');
    });

    it('应检测 V-02 违规（禁止决策句式）', () => {
      const results = validateOutput('你应该选择第一人称来写', mockRulesConfig);
      const v02 = results.find(r => r.ruleId === 'V-02');
      expect(v02).toBeDefined();
      expect(v02!.passed).toBe(false);
      expect(v02!.matchedPatterns).toContain('你应该');
    });

    it('应检测 V-03 违规（禁止暴露编号）', () => {
      const results = validateOutput('检测到 P001 说明书症候', mockRulesConfig);
      const v03 = results.find(r => r.ruleId === 'V-03');
      expect(v03).toBeDefined();
      expect(v03!.passed).toBe(false);
      expect(v03!.matchedPatterns).toContain('P001');
    });

    it('合规文本应全部通过', () => {
      const text = '我觉得如果从主角视角切入会怎样？这里有两个方向可以考虑。';
      const results = validateOutput(text, mockRulesConfig);
      expect(results.every(r => r.passed)).toBe(true);
    });

    it('应按角色过滤规则', () => {
      const text = '在 [[chapter:第三章]] 中';
      const results = validateOutput(text, mockRulesConfig, { roleId: 'clown' });
      // V-04 不适用于 clown，所以所有人通过
      const v04 = results.find(r => r.ruleId === 'V-04');
      expect(v04).toBeUndefined();
    });

    it('空配置应返回空数组', () => {
      const emptyConfig: RulesConfig = { version: '0', updatedAt: '', description: '', rules: [] };
      const results = validateOutput('任何文本', emptyConfig);
      expect(results).toEqual([]);
    });
  });

  describe('hasFatalViolations', () => {
    it('有致命违规时返回 true', () => {
      const results = validateOutput('你应该选择第一人称', mockRulesConfig);
      expect(hasFatalViolations(results)).toBe(true);
    });

    it('无致命违规时返回 false', () => {
      const results = validateOutput('合规文本', mockRulesConfig);
      expect(hasFatalViolations(results)).toBe(false);
    });
  });

  describe('summarizeViolations', () => {
    it('应生成违规摘要', () => {
      const results = validateOutput('你应该选择第一人称，检测到 P001', mockRulesConfig);
      const summary = summarizeViolations(results);
      expect(summary).not.toContain('V-01');
      expect(summary).toContain('V-02');
      expect(summary).toContain('V-03');
    });

    it('无违规时应返回空字符串', () => {
      const results = validateOutput('合规文本', mockRulesConfig);
      expect(summarizeViolations(results)).toBe('');
    });
  });
});
