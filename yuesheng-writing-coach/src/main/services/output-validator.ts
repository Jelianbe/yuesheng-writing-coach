/**
 * 配置驱动输出验证器
 *
 * 职责：读取 teaching-rules.json / attitude-rhythm.json / feedback-structure.json，
 * 对 LLM 输出做合规校验。纯函数实现，可脱机单元测试。
 *
 * 设计原则：
 * - 规则定义在 JSON 配置中，新增规则只需改配置无需改代码
 * - 每条规则有独立的检测模式（regex/keyword/llm）
 * - 校验结果可聚合，单次调用返回全部违规
 */

import * as fs from 'fs';
import * as path from 'path';

// ======================== 类型定义 ========================

export type ValidationLevel = 'fatal' | 'warning' | 'suggestion';

export interface ValidationRule {
  id: string;
  level: ValidationLevel;
  description: string;
  detectPattern: {
    type: 'regex' | 'keyword' | 'llm';
    patterns: string[];
  };
  applicableRoles: string[];
  examples: {
    bad: string[];
    good: string[];
  };
  testCases: Array<{
    input: string;
    expected: 'pass' | 'fail';
    matchedRules?: string[];
  }>;
}

export interface RulesConfig {
  version: string;
  updatedAt: string;
  description: string;
  rules: ValidationRule[];
}

export interface ValidationResult {
  ruleId: string;
  level: ValidationLevel;
  description: string;
  passed: boolean;
  matchedPatterns?: string[];
}

export type ValidatorOptions = {
  resourcesRoot?: string;
  roleId?: string;
};

// ======================== 默认配置路径 ========================

const DEFAULT_CONFIG_PATH = 'config/teaching-rules.json';

// ======================== 核心函数 ========================

/**
 * 加载教学规则配置
 */
export function loadRulesConfig(resourcesRoot: string): RulesConfig {
  try {
    const configPath = path.join(resourcesRoot, DEFAULT_CONFIG_PATH);
    const raw = fs.readFileSync(configPath, 'utf-8');
    return JSON.parse(raw) as RulesConfig;
  } catch {
    return { version: '0', updatedAt: '', description: 'fallback', rules: [] };
  }
}

/**
 * 检测文本是否匹配关键词模式
 */
function detectKeywords(text: string, patterns: string[]): string[] {
  const matched: string[] = [];
  for (const pattern of patterns) {
    if (text.includes(pattern)) {
      matched.push(pattern);
    }
  }
  return matched;
}

/**
 * 检测文本是否匹配正则模式
 */
function detectRegex(text: string, patterns: string[]): string[] {
  const matched: string[] = [];
  for (const pattern of patterns) {
    try {
      const regex = new RegExp(pattern);
      if (regex.test(text)) {
        matched.push(pattern);
      }
    } catch {
      // 忽略无效的正则表达式
    }
  }
  return matched;
}

/**
 * 对单条输出执行全部适用规则的合规校验
 *
 * @param output - LLM 生成的回复文本
 * @param rulesConfig - 规则配置（可通过 loadRulesConfig 加载）
 * @param options - 可选参数（resourcesRoot 用于降级加载，roleId 用于按角色过滤）
 * @returns 校验结果数组（空数组 = 全部通过）
 */
export function validateOutput(
  output: string,
  rulesConfig?: RulesConfig,
  options?: ValidatorOptions,
): ValidationResult[] {
  let config = rulesConfig;

  if (!config && options?.resourcesRoot) {
    config = loadRulesConfig(options.resourcesRoot);
  }

  if (!config || config.rules.length === 0) {
    return [];
  }

  const results: ValidationResult[] = [];

  for (const rule of config.rules) {
    // 按角色过滤
    if (options?.roleId && !rule.applicableRoles.includes(options.roleId)) {
      continue;
    }

    let matchedPatterns: string[] = [];

    switch (rule.detectPattern.type) {
      case 'keyword':
        matchedPatterns = detectKeywords(output, rule.detectPattern.patterns);
        break;
      case 'regex':
        matchedPatterns = detectRegex(output, rule.detectPattern.patterns);
        break;
      case 'llm':
        // LLM 类型检测需要调用 LLM，这里不做实现
        // 由外部调用者自行处理
        break;
    }

    results.push({
      ruleId: rule.id,
      level: rule.level,
      description: rule.description,
      passed: matchedPatterns.length === 0,
      matchedPatterns: matchedPatterns.length > 0 ? matchedPatterns : undefined,
    });
  }

  return results;
}

/**
 * 检查是否有致命级别违规
 */
export function hasFatalViolations(results: ValidationResult[]): boolean {
  return results.some(r => r.level === 'fatal' && !r.passed);
}

/**
 * 获取违规摘要（按级别分组）
 */
export function summarizeViolations(results: ValidationResult[]): string {
  const levels: ValidationLevel[] = ['fatal', 'warning', 'suggestion'];
  const lines: string[] = [];

  for (const level of levels) {
    const violations = results.filter(r => r.level === level && !r.passed);
    if (violations.length > 0) {
      const label = level === 'fatal' ? '🔴 致命' : level === 'warning' ? '🟡 重要' : '🟢 建议';
      lines.push(`${label} (${violations.length})`);
      for (const v of violations) {
        lines.push(`  - ${v.ruleId}: ${v.description}`);
        if (v.matchedPatterns) {
          lines.push(`    匹配: ${v.matchedPatterns.join(', ')}`);
        }
      }
    }
  }

  return lines.join('\n');
}
