/**
 * Sprint 14-prior 验收测试
 *
 * 目标（解决 D-DEBT-11 + D-DEBT-09）：
 * 1. dispatcher coreSubsetOnly 只选 isCoreSubset=true 的 SKILL
 * 2. dispatcher maxTokens 按 tokenPriority 截断
 * 3. dispatcher 默认 P2+ 加载核心子集体积 < 4K tokens
 * 4. dispatcher 加载 v5 降级路径不受影响
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import { SkillDispatcher } from '../skill-dispatcher';

const TEST_SKILLS_DIR = path.join(os.tmpdir(), 'test-sprint-14-prior-' + Date.now());

beforeAll(() => {
  fs.mkdirSync(TEST_SKILLS_DIR, { recursive: true });

  // 模拟 Sprint 14-prior 拆分后的 SKILL 文件
  const skills = [
    // core 子集（拆分后）
    {
      id: 'core-iron-triangle',
      tokens: 600,
      tokenPriority: 10,
      isCoreSubset: true,
      parentId: 'core-identity',
      phases: ['P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    },
    {
      id: 'core-product-identity',
      tokens: 900,
      tokenPriority: 9,
      isCoreSubset: true,
      parentId: 'core-identity',
      phases: ['P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    },
    // 已废弃的聚合入口（仍然存在但 isCoreSubset=false）
    {
      id: 'core-identity',
      tokens: 1500,
      tokenPriority: 10,
      isCoreSubset: false,
      parentId: null,
      phases: ['P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    },
    // 其他 SKILL（always）
    {
      id: 'teaching-strategy',
      tokens: 8000,
      tokenPriority: 5,
      isCoreSubset: false,
      parentId: null,
      phases: ['P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    },
    {
      id: 'validation-rules',
      tokens: 5000,
      tokenPriority: 5,
      isCoreSubset: false,
      parentId: null,
      phases: ['P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    },
    {
      id: 'scenario-rules',
      tokens: 4000,
      tokenPriority: 5,
      isCoreSubset: false,
      parentId: null,
      phases: ['P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    },
    // 条件加载 SKILL
    {
      id: 'reference-drawer',
      tokens: 2000,
      tokenPriority: 7,
      isCoreSubset: false,
      parentId: null,
      phases: ['P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    },
    {
      id: 'feedback-cognition',
      tokens: 3000,
      tokenPriority: 6,
      isCoreSubset: false,
      parentId: null,
      phases: ['P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
    },
  ];

  for (const s of skills) {
    const yaml = [
      '---',
      `id: ${s.id}`,
      `estimatedTokens: ${s.tokens}`,
      `tokenPriority: ${s.tokenPriority}`,
      `isCoreSubset: ${s.isCoreSubset}`,
      `parentId: ${s.parentId === null ? 'null' : s.parentId}`,
      `loadWhen:`,
      `  phases: [${s.phases.join(', ')}]`,
      `  attitudes: [doubao, yuesheng, sensei]`,
      '---',
      '',
      `# ${s.id} content`,
    ].join('\n');
    fs.writeFileSync(path.join(TEST_SKILLS_DIR, `${s.id}.md`), yaml);
  }
});

afterAll(() => {
  fs.rmSync(TEST_SKILLS_DIR, { recursive: true, force: true });
});

describe('Sprint 14-prior 验收（D-DEBT-11 体积优化）', () => {
  it('coreSubsetOnly=true 只选 isCoreSubset=true 的 SKILL', () => {
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    const skills = d.selectForPhase('P2_PRACTICE_LOOP', 'yuesheng', { coreSubsetOnly: true });
    const ids = skills.map(s => s.meta.id).sort();
    expect(ids).toEqual(['core-iron-triangle', 'core-product-identity']);
  });

  it('P0+P1 不启用 coreSubsetOnly 时：仍可选到全量 SKILL（v5 降级前向兼容）', () => {
    // Sprint 14-prior: P0/P1 走 v5 降级，不调用 dispatcher
    // 但 dispatcher 接口仍能选全量（保留向后兼容能力）
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    const skills = d.selectForPhase('P0_INIT', 'yuesheng');
    expect(skills.length).toBeGreaterThan(2); // 不止核心子集
  });

  it('P2+ coreSubsetOnly + 默认 budget: 核心子集体积 < 4K tokens', () => {
    // 解决 D-DEBT-11 的关键断言：体积目标 < 4K tokens
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    const tokens = d.estimateTokens('P2_PRACTICE_LOOP', 'yuesheng', {
      coreSubsetOnly: true,
      maxTokens: 4000,
    });
    // 实际: core-iron-triangle (600) + core-product-identity (900) = 1500 tokens
    expect(tokens).toBeLessThan(4000);
    expect(tokens).toBe(1500);
  });

  it('maxTokens 截断：按 tokenPriority 降序保留高优先级', () => {
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    // budget=2000: priority=10 的两个 SKILL (600 和 1500) 都能装
    // priority=9+ 的 900 加上 1500 = 2400 > 2000, 所以 product-identity 应被截断
    const skills = d.selectForPhase('P2_PRACTICE_LOOP', 'yuesheng', {
      maxTokens: 2000,
    });
    const totalTokens = skills.reduce((s, sk) => s + sk.meta.estimatedTokens, 0);
    expect(totalTokens).toBeLessThanOrEqual(2000);
    // 至少应包含高优先级 (10) 的 SKILL
    const hasPriority10 = skills.some(s => (s.meta.tokenPriority ?? 5) >= 10);
    expect(hasPriority10).toBe(true);
    // teaching-strategy (8000) 超出预算必被截断
    expect(skills.map(s => s.meta.id)).not.toContain('teaching-strategy');
  });

  it('maxTokens 截断：极端小预算（500 tokens）→ 只保留最高优先级', () => {
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    const skills = d.selectForPhase('P2_PRACTICE_LOOP', 'yuesheng', {
      maxTokens: 500,
    });
    // core-iron-triangle (600) 装不下
    // 预期：返回空或包含 < 500 的 SKILL（没有这样的）
    expect(skills.length).toBe(0);
  });

  it('无 coreSubsetOnly 时：原 Sprint 13 行为不变（不破坏向后兼容）', () => {
    // Sprint 13 测试期望：P2_PRACTICE_LOOP 加载 6 个 SKILL（25K tokens）
    // Sprint 14-prior: 加载 8 个 SKILL（原 6 + 2 核心子集 = 8）
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    const skills = d.selectForPhase('P2_PRACTICE_LOOP', 'doubao');
    expect(skills.length).toBe(8);
  });

  it('tokenPriority 范围校验：超出 [1,10] 抛错', () => {
    const badDir = path.join(os.tmpdir(), 'test-bad-priority-' + Date.now());
    fs.mkdirSync(badDir, { recursive: true });
    fs.writeFileSync(
      path.join(badDir, 'bad.md'),
      `---
id: bad
estimatedTokens: 100
tokenPriority: 99
isCoreSubset: true
loadWhen:
  phases: [P0_INIT]
  attitudes: [yuesheng]
---

# bad
`,
    );
    try {
      const d = new SkillDispatcher();
      expect(() => d.load(badDir)).toThrow(/tokenPriority out of range/);
    } finally {
      fs.rmSync(badDir, { recursive: true, force: true });
    }
  });
});

describe('Sprint 14-prior 验收（D-DEBT-09 phase 注入）', () => {
  it('loadCorePrompt 接口接受 phase 参数（类型签名验证）', () => {
    // 这里只验证类型签名存在，不实际调用（dynamic-context 是 private 加载）
    // 通过读源码确认 loadContext 已接受 phase 参数
    const source = fs.readFileSync(
      path.resolve(__dirname, '../dynamic-context.service.ts'),
      'utf-8',
    );
    expect(source).toMatch(/loadContext\(syndromeIds:\s*string\[\],\s*phase:\s*TeachingPhase\s*=\s*'P0_INIT'\)/);
    expect(source).toMatch(/loadCorePrompt\(phase:\s*TeachingPhase\s*=\s*'P0_INIT'\)/);
  });

  it('loadSystemPrompt 从 stateContextGetter 注入 phase（源码验证）', () => {
    const source = fs.readFileSync(
      path.resolve(__dirname, '../prompt-loader.ts'),
      'utf-8',
    );
    // 验证 loadSystemPrompt 调用 loadContext 时传入了 phase
    expect(source).toMatch(/this\.dynamicContextService\.loadContext\(\s*syndromeIds\s*\?\?\s*\[\],\s*phase/);
    // 验证从 stateContextGetter 获取 phase
    expect(source).toMatch(/this\.stateContextGetter\(sessionId\)/);
  });
});
