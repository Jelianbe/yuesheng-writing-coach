/**
 * Prompt Contract 端到端验证(Sprint 20 增量 3)
 *
 * 目的:加载真实 .md 提示词文件 vs 真实运行时数据源,验证契约拦截行为可观察
 *
 * 数据源:
 * - resources/prompts/skills/*.md → availableSkills(文件名去后缀)
 * - resources/config/technique-library.json → availableTechniques(128 条)
 * - IPC_CHANNELS 关键值(简版) → availableTools
 * - mock-orchestrator MOCK_CONTRACT.emits_events → availableEvents
 *
 * 依据:dev-docs/tasks/sprint-20-plan.md §增量 3 / D-054 教训
 */

import { describe, it, expect } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { parsePromptContract, validateContract, PromptContractError } from '../prompt-contract';

// __dirname 向上 6 层 = 项目根(从 src/main/domains/03-teaching/conversation/__tests__/ 起)
const ROOT = path.resolve(__dirname, '../../../../../../');
const PROMPTS_DIR = path.join(ROOT, 'resources/prompts');
const CONFIG_DIR = path.join(ROOT, 'resources/config');

function extractContractBlock(md: string): string {
  const m = md.match(/```yaml\r?\n([\s\S]*?)\r?\n```/);
  if (!m) throw new Error('未找到 ```yaml 契约块');
  return m[1];
}

function loadContractFromMd(mdPath: string) {
  const md = fs.readFileSync(mdPath, 'utf-8');
  return parsePromptContract(extractContractBlock(md));
}

function buildRuntimeEnv() {
  const skillsDir = path.join(PROMPTS_DIR, 'skills');
  const availableSkills = fs.readdirSync(skillsDir)
    .filter(f => f.endsWith('.md'))
    .map(f => f.replace(/\.md$/, ''));

  const techPath = path.join(CONFIG_DIR, 'technique-library.json');
  const techData = JSON.parse(fs.readFileSync(techPath, 'utf-8')) as Array<{ id: string }>;
  const availableTechniques = techData.map(t => t.id);

  const availableTools = [
    'chapter:get', 'chapter:list', 'chapter:create', 'chapter:update', 'chapter:delete',
    'diagnosis:query', 'diagnosis:submit_rewrite', 'diagnosis:get_comparison',
    'training:recommend', 'training:assign', 'training:complete', 'training:skip',
    'training:history', 'training:submit', 'training:evaluate',
    'session:list', 'session:create', 'session:delete', 'session:rename',
    'session:get_messages', 'session:list_with_meta', 'session:update_title',
    'session:search_messages', 'session:is_new_user',
  ];

  const availableEvents = [
    'chat:token', 'chat:intent', 'chat:phase_transition', 'chat:done', 'chat:error',
    'diagnosis:extracted', 'training:triggered',
  ];

  return { availableSkills, availableTechniques, availableTools, availableEvents };
}

const ENV = buildRuntimeEnv();

interface ValidationOutcome {
  pass: boolean;
  mismatches: Array<{ category: string; missing: string[] }>;
  contractSummary: {
    skills: number;
    techniques: string[];
    tools: number;
    events: number;
  };
}

function validateAndReport(label: string, mdPath: string): ValidationOutcome {
  const contract = loadContractFromMd(mdPath);
  const summary = {
    skills: contract.required_skills.length,
    techniques: contract.required_techniques,
    tools: contract.required_tools.length,
    events: contract.emits_events.length,
  };

  console.log(`\n=== 验证 ${label} ===`);
  console.log('契约摘要:', JSON.stringify(summary, null, 2));

  try {
    validateContract(contract, ENV, label);
    console.log(`✅ PASS - 契约与运行时环境兼容`);
    return { pass: true, mismatches: [], contractSummary: summary };
  } catch (err) {
    if (err instanceof PromptContractError) {
      console.error(`❌ FAIL - 契约校验失败(${err.mismatches.length} 类不兼容):`);
      for (const m of err.mismatches) {
        console.error(`  [${m.category}] 缺少 ${m.missing.length} 项: ${m.missing.join(', ')}`);
      }
      console.error(`\n  错误信息原文:\n${err.message.split('\n').map(l => '    ' + l).join('\n')}`);
      return { pass: false, mismatches: err.mismatches, contractSummary: summary };
    }
    throw err;
  }
}

describe('prompt-contract 端到端验证 (Sprint 20 增量 3)', () => {
  it('打印运行时环境统计(供调试)', () => {
    console.log('\n=== 运行时环境 ===');
    console.log(`availableSkills (${ENV.availableSkills.length} 项):`, ENV.availableSkills.join(', '));
    const techPrefixes = [...new Set(ENV.availableTechniques.map(id => id.split('-')[0]))];
    console.log(`availableTechniques (${ENV.availableTechniques.length} 项,前缀 ${techPrefixes.length} 种):`, techPrefixes.join(', '));
    console.log(`availableTools (${ENV.availableTools.length} 个 IPC 频道值):`, `${ENV.availableTools.slice(0, 5).join(', ')}...`);
    console.log(`availableEvents (${ENV.availableEvents.length} 项):`, ENV.availableEvents.join(', '));
    expect(ENV.availableSkills.length).toBeGreaterThan(0);
    expect(ENV.availableTechniques.length).toBeGreaterThan(0);
  });

  it('V5.0.0-draft vs 真实运行时 → 应捕获契约/运行时错配', () => {
    const mdPath = path.join(PROMPTS_DIR, 'yuesheng-prompt-v5.0.0-draft.md');
    const result = validateAndReport('V5.0.0-draft', mdPath);

    expect(result.pass).toBe(false);
    expect(result.mismatches.some(m => m.category === 'techniques')).toBe(true);
    expect(result.mismatches.some(m => m.category === 'tools')).toBe(true);
  });

  it('V5.0.1 OFFICIAL vs 真实运行时 → 契约对齐,应通过校验', () => {
    const mdPath = path.join(PROMPTS_DIR, 'yuesheng-prompt-v5.0.1.md');
    const result = validateAndReport('V5.0.1 OFFICIAL', mdPath);

    // OFFICIAL 收尾: 移除 TQ-999 + 修复 techniques/tools 与运行时对齐
    expect(result.pass).toBe(true);
    expect(result.mismatches).toEqual([]);
  });

  it('契约拦截机制 → 故意注入 TQ-999 的契约,应被启动校验拦截', () => {
    // 构造含 TQ-999 的内联契约,验证 validateContract 拦截行为
    // (OFFICIAL 版本已移除 TQ-999,这里验证"如果注入会怎样"以固化契约防线)
    const maliciousContract = {
      required_phases: ['trust_building', 'requirement', 'diagnosis', 'training', 'reflection'] as Array<'trust_building' | 'requirement' | 'diagnosis' | 'training' | 'reflection'>,
      required_skills: ENV.availableSkills.slice(0, 4),
      required_techniques: [...ENV.availableTechniques.slice(0, 3), 'TQ-999'],
      required_tools: ENV.availableTools.slice(0, 3),
      emits_events: ENV.availableEvents.slice(0, 3),
    };

    expect(() => validateContract(maliciousContract, ENV, 'malicious-with-TQ999')).toThrow(PromptContractError);
    try {
      validateContract(maliciousContract, ENV, 'malicious-with-TQ999');
    } catch (err) {
      const e = err as PromptContractError;
      const techMismatch = e.mismatches.find(m => m.category === 'techniques');
      expect(techMismatch).toBeDefined();
      if (!techMismatch) throw new Error('techMismatch missing');
      expect(techMismatch.missing).toEqual(['TQ-999']);
    }
  });
});
