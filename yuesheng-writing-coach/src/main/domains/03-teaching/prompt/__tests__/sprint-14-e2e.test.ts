/**
 * Sprint 14 E2E 集成测试
 *
 * 覆盖 Plan 中 4 个核心场景：
 * 1. P0 + doubao → core subset + token 预算（v5 降级路径）
 * 2. P2 + sensei → dispatcher 核心子集 + 删鼓励话术
 * 3. P3 + safety word → 跳过有 conditions 的 SKILL
 * 4. 循环依赖配置 → 启动失败（fail-fast）
 *
 * 设计依据：dev-docs/designs/sprint-14-plan.md T14-7
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { SkillDispatcher } from '../skill-dispatcher';
import { AttitudeFilter } from '../attitude-filter';
import type { Skill } from '../skill-metadata';

const TEST_DIR = path.join(os.tmpdir(), 'test-sprint-14-e2e-' + Date.now());
const TEST_CONFIG = path.join(TEST_DIR, 'attitude-filter.json');

beforeAll(() => {
  fs.mkdirSync(TEST_DIR, { recursive: true });
  fs.writeFileSync(TEST_CONFIG, JSON.stringify({
    version: '1.0',
    rules: {
      doubao: { removePatterns: [], replacePatterns: [] },
      yuesheng: { removePatterns: [], replacePatterns: [] },
      sensei: {
        removePatterns: [
          '(?:加油|棒|真棒|非常好|继续努力)(?=[，。！？、\\s])',
        ],
        replacePatterns: [
          { pattern: '希望.{0,10}', replacement: '' },
        ],
      },
    },
    minContentLength: { default: 50 },
  }, null, 2));
});

afterAll(() => {
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
});

/** 工具函数：构造一个 80 字符的技术性内容（含标点等避免长度保护触发） */
const technicalContent = (topic: string) =>
  `这一段在描写 ${topic} 时需要更深层的笔触。通过细节让读者感受人物的内心冲突。` +
  `视角要保持一致，节奏要自然推进，让故事流畅地展开。`;

describe('Sprint 14 E2E 场景 1：P0 + doubao → 核心子集 + 预算', () => {
  it('P0 + coreSubsetOnly + maxTokens → 体积 < 预算 + 加载核心子集', () => {
    // 构造 3 个 SKILL：2 个核心子集 + 1 个非核心
    const skillsDir = path.join(TEST_DIR, 's1');
    fs.mkdirSync(skillsDir, { recursive: true });

    // 核心子集 1：铁三角 (P0 always load)
    fs.writeFileSync(path.join(skillsDir, 'core-iron-triangle.md'), `---
id: core-iron-triangle
estimatedTokens: 600
isCoreSubset: true
tokenPriority: 10
loadWhen:
  phases: [P0_INIT, P1_WORLD]
  attitudes: [doubao, yuesheng, sensei]
---

${technicalContent('铁三角基础')}`);

    // 核心子集 2：教学策略 (P0 always load)
    fs.writeFileSync(path.join(skillsDir, 'teaching-strategy.md'), `---
id: teaching-strategy
estimatedTokens: 400
isCoreSubset: true
tokenPriority: 8
loadWhen:
  phases: [P0_INIT, P1_WORLD, P2_PRACTICE_LOOP]
  attitudes: [doubao, yuesheng, sensei]
---

${technicalContent('教学策略')}`);

    // 非核心：参考抽屉 (P2+ only)
    fs.writeFileSync(path.join(skillsDir, 'reference-drawer.md'), `---
id: reference-drawer
estimatedTokens: 1000
isCoreSubset: false
tokenPriority: 5
loadWhen:
  phases: [P2_PRACTICE_LOOP, P3_TRAINING]
  attitudes: [doubao, yuesheng]
---

${technicalContent('参考抽屉')}`);

    const d = new SkillDispatcher();
    d.load(skillsDir);

    // P0 + doubao + coreSubsetOnly + maxTokens=2000
    const skills = d.selectForPhase('P0_INIT', 'doubao', {
      coreSubsetOnly: true,
      maxTokens: 2000,
    });
    const totalTokens = skills.reduce((s, x) => s + x.meta.estimatedTokens, 0);

    expect(skills.length).toBe(2); // 仅核心子集
    expect(skills.every(s => s.meta.isCoreSubset === true)).toBe(true);
    expect(totalTokens).toBeLessThanOrEqual(2000);
    expect(totalTokens).toBe(1000); // 600 + 400

    fs.rmSync(skillsDir, { recursive: true, force: true });
  });
});

describe('Sprint 14 E2E 场景 2：P2 + sensei → 核心子集 + 删鼓励话术', () => {
  it('P2 + sensei → composePrompt 过滤鼓励话术', () => {
    const skillsDir = path.join(TEST_DIR, 's2');
    fs.mkdirSync(skillsDir, { recursive: true });

    // 包含"加油"等鼓励话术的 SKILL
    const longContent =
      technicalContent('角色心理') +
      '加油！这个想法非常棒！希望你能继续努力。' +
      technicalContent('场景描写');

    fs.writeFileSync(path.join(skillsDir, 'feedback-cognition.md'), `---
id: feedback-cognition
estimatedTokens: 500
tokenPriority: 7
loadWhen:
  phases: [P2_PRACTICE_LOOP, P3_TRAINING]
  attitudes: [doubao, yuesheng, sensei]
---

${longContent}`);

    const d = new SkillDispatcher();
    d.load(skillsDir);
    d.setAttitudeFilter(new AttitudeFilter(TEST_CONFIG));

    const result = d.composePrompt('P2_PRACTICE_LOOP', 'sensei');

    // 验证：sensei 档不含鼓励话术
    expect(result).not.toContain('加油');
    expect(result).not.toContain('非常棒');
    // 验证：保留技术性内容
    expect(result).toContain('角色心理');
    expect(result).toContain('场景描写');

    fs.rmSync(skillsDir, { recursive: true, force: true });
  });
});

describe('Sprint 14 E2E 场景 3：safety word 触发时跳过 condition 约束的 SKILL', () => {
  it('safetyWord=true → 跳过有 user.safetyWord IS_NOT true 约束的 SKILL', () => {
    const d = new SkillDispatcher();
    // SKILL A：必须 safetyWord 未触发时加载
    (d as unknown as { skills: Map<string, Skill> }).skills.set('sk-strict', {
      meta: {
        id: 'sk-strict',
        estimatedTokens: 300,
        loadWhen: {
          phases: ['P3_TRAINING'],
          attitudes: ['doubao', 'yuesheng', 'sensei'],
          conditions: [
            { type: 'user.safetyWord', op: 'IS_NOT', value: true },
          ],
        },
      },
      content: technicalContent('严格训练'),
    });
    // SKILL B：无条件约束
    (d as unknown as { skills: Map<string, Skill> }).skills.set('sk-relaxed', {
      meta: {
        id: 'sk-relaxed',
        estimatedTokens: 200,
        loadWhen: {
          phases: ['P3_TRAINING'],
          attitudes: ['doubao', 'yuesheng', 'sensei'],
        },
      },
      content: technicalContent('放松训练'),
    });
    (d as unknown as { loaded: boolean }).loaded = true;

    // safetyWord=false → 加载全部 2 个
    const normal = d.selectForPhase('P3_TRAINING', 'doubao', {}, { safetyWord: false });
    expect(normal.map(s => s.meta.id).sort()).toEqual(['sk-relaxed', 'sk-strict']);

    // safetyWord=true → 仅 sk-relaxed
    const safe = d.selectForPhase('P3_TRAINING', 'doubao', {}, { safetyWord: true });
    expect(safe.map(s => s.meta.id)).toEqual(['sk-relaxed']);
  });

  it('evidence.quality=low → 加载强化反馈 SKILL；=high → 不加载', () => {
    const d = new SkillDispatcher();
    (d as unknown as { skills: Map<string, Skill> }).skills.set('sk-reinforce', {
      meta: {
        id: 'sk-reinforce',
        estimatedTokens: 250,
        loadWhen: {
          phases: ['P2_PRACTICE_LOOP'],
          attitudes: ['doubao'],
          conditions: [
            { type: 'evidence.quality', op: 'IN', values: ['low', 'medium'] },
          ],
        },
      },
      content: technicalContent('强化反馈'),
    });
    (d as unknown as { loaded: boolean }).loaded = true;

    const low = d.selectForPhase('P2_PRACTICE_LOOP', 'doubao', {}, { evidenceQuality: 'low' });
    expect(low.map(s => s.meta.id)).toEqual(['sk-reinforce']);

    const high = d.selectForPhase('P2_PRACTICE_LOOP', 'doubao', {}, { evidenceQuality: 'high' });
    expect(high).toEqual([]);
  });
});

describe('Sprint 14 E2E 场景 4：循环依赖配置 → 启动失败', () => {
  it('SKILL A 依赖 B，B 依赖 A → load() 抛错（fail-fast）', () => {
    const skillsDir = path.join(TEST_DIR, 's4');
    fs.mkdirSync(skillsDir, { recursive: true });

    fs.writeFileSync(path.join(skillsDir, 'a.md'), `---
id: a
estimatedTokens: 100
depends: [b]
loadWhen:
  phases: [P0_INIT]
  attitudes: [doubao]
---

${technicalContent('A')}`);

    fs.writeFileSync(path.join(skillsDir, 'b.md'), `---
id: b
estimatedTokens: 100
depends: [a]
loadWhen:
  phases: [P0_INIT]
  attitudes: [doubao]
---

${technicalContent('B')}`);

    const d = new SkillDispatcher();
    expect(() => d.load(skillsDir)).toThrow(/cycle|循环|invalid/i);

    fs.rmSync(skillsDir, { recursive: true, force: true });
  });

  it('缺失依赖 → load() 抛错', () => {
    const skillsDir = path.join(TEST_DIR, 's4b');
    fs.mkdirSync(skillsDir, { recursive: true });

    fs.writeFileSync(path.join(skillsDir, 'a.md'), `---
id: a
estimatedTokens: 100
depends: [nonexistent]
loadWhen:
  phases: [P0_INIT]
  attitudes: [doubao]
---

${technicalContent('A')}`);

    const d = new SkillDispatcher();
    expect(() => d.load(skillsDir)).toThrow(/missing|缺失|nonexistent|invalid/i);

    fs.rmSync(skillsDir, { recursive: true, force: true });
  });
});

describe('Sprint 14 E2E 场景 5：完整 phase + attitude + conditions 矩阵', () => {
  it('完整 5 phase × 3 attitude × conditions 矩阵运行无错', () => {
    const skillsDir = path.join(TEST_DIR, 's5');
    fs.mkdirSync(skillsDir, { recursive: true });

    // 构造覆盖全 phase / attitude / conditions 的 SKILL
    const skills = [
      { id: 'p0-core', phase: 'P0_INIT', attitude: 'doubao,yuesheng,sensei', conditions: '' },
      { id: 'p1-core', phase: 'P1_WORLD', attitude: 'doubao,yuesheng,sensei', conditions: '' },
      { id: 'p2-core', phase: 'P2_PRACTICE_LOOP', attitude: 'doubao,yuesheng', conditions: '' },
      { id: 'p2-sensei', phase: 'P2_PRACTICE_LOOP', attitude: 'sensei', conditions: '' },
      { id: 'p3-strict', phase: 'P3_TRAINING', attitude: 'doubao,yuesheng', conditions: '\n  conditions: [low]' },
      { id: 'p4-review', phase: 'P4_REVIEW', attitude: 'doubao,yuesheng,sensei', conditions: '' },
    ];

    for (const s of skills) {
      const yaml = `---
id: ${s.id}
estimatedTokens: 100
loadWhen:
  phases: [${s.phase}]
  attitudes: [${s.attitude}]${s.conditions}
---

${technicalContent(s.id)}`;
      fs.writeFileSync(path.join(skillsDir, `${s.id}.md`), yaml);
    }

    const d = new SkillDispatcher();
    d.load(skillsDir);
    d.setAttitudeFilter(new AttitudeFilter(TEST_CONFIG));

    const phases: Array<'P0_INIT' | 'P1_WORLD' | 'P2_PRACTICE_LOOP' | 'P3_TRAINING' | 'P4_REVIEW'> = [
      'P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW',
    ];
    const attitudes: Array<'doubao' | 'yuesheng' | 'sensei'> = ['doubao', 'yuesheng', 'sensei'];

    // 矩阵运行：每个 (phase, attitude) 都应正常返回
    for (const phase of phases) {
      for (const attitude of attitudes) {
        const ctx = { evidenceQuality: 'low' as const, safetyWord: false };
        const result = d.composePrompt(phase, attitude, {}, ctx);
        // 不抛错，且不含"加油"（sensei 档态度过滤）
        if (attitude === 'sensei') {
          expect(result).not.toContain('加油');
        }
        expect(typeof result).toBe('string');
      }
    }

    // safety word 触发：p3-strict 不应加载
    const safetyCtx = { evidenceQuality: 'low' as const, safetyWord: true };
    const safeP3 = d.selectForPhase('P3_TRAINING', 'doubao', {}, safetyCtx);
    expect(safeP3.map(s => s.meta.id)).not.toContain('p3-strict');

    fs.rmSync(skillsDir, { recursive: true, force: true });
  });
});
