/**
 * Sprint 14 E2E 集成测试
 *
 * 覆盖 Plan 中 4 个核心场景：
 * 1. P0 + doubao → core subset + token 预算（v5 降级路径）
 * 2. P2 + sensei → dispatcher 加载 attitude-sensei SKILL（LLM 行为指令）
 * 3. P3 + safety word → 跳过有 conditions 的 SKILL
 * 4. 循环依赖配置 → 启动失败（fail-fast）
 *
 * 设计依据：dev-docs/designs/sprint-14-plan.md T14-7
 *
 * 反思（D-033）：T14-4 早期实现是 AttitudeFilter 规则屏蔽（用正则删除鼓励话术），
 * 违反"AI 驱动优于规则约束"原则。已重构为 attitude-*.md SKILL 文件，
 * 由 LLM 自主理解行为指令。E2E 场景 2 验证 SKILL 加载而非过滤后内容。
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { SkillDispatcher } from '../skill-dispatcher';

const TEST_DIR = path.join(os.tmpdir(), 'test-sprint-14-e2e-' + Date.now());

beforeAll(() => {
  fs.mkdirSync(TEST_DIR, { recursive: true });
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

describe('Sprint 14 E2E 场景 2：P2 + sensei → 加载 attitude-sensei SKILL', () => {
  it('P2 + sensei → composePrompt 包含 attitude-sensei 行为指令', () => {
    const skillsDir = path.join(TEST_DIR, 's2');
    fs.mkdirSync(skillsDir, { recursive: true });

    // 加载态度指令 SKILL（每个 attitude 档位一个）
    fs.writeFileSync(path.join(skillsDir, 'attitude-doubao.md'), `---
id: attitude-doubao
estimatedTokens: 100
loadWhen:
  phases: [P0_INIT, P1_WORLD, P2_PRACTICE_LOOP]
  attitudes: [doubao]
---

# 态度：豆包（默认）
作为写作陪练伙伴，氛围轻松友好。`);

    fs.writeFileSync(path.join(skillsDir, 'attitude-sensei.md'), `---
id: attitude-sensei
estimatedTokens: 150
loadWhen:
  phases: [P0_INIT, P1_WORLD, P2_PRACTICE_LOOP]
  attitudes: [sensei]
---

# 态度：Sensei（严格技术教练）
用 AI 自己的语言系统表达技术反馈，避免空泛鼓励话术。`);

    fs.writeFileSync(path.join(skillsDir, 'feedback-cognition.md'), `---
id: feedback-cognition
estimatedTokens: 500
loadWhen:
  phases: [P2_PRACTICE_LOOP, P3_TRAINING]
  attitudes: [doubao, yuesheng, sensei]
---

${technicalContent('反馈认知')}`);

    const d = new SkillDispatcher();
    d.load(skillsDir);

    // P2 + sensei → 应加载 attitude-sensei（不加载 attitude-doubao）
    const senseiSkills = d.selectForPhase('P2_PRACTICE_LOOP', 'sensei');
    const senseiIds = senseiSkills.map(s => s.meta.id);
    expect(senseiIds).toContain('attitude-sensei');
    expect(senseiIds).not.toContain('attitude-doubao');

    const result = d.composePrompt('P2_PRACTICE_LOOP', 'sensei');
    expect(result).toContain('Sensei');
    expect(result).toContain('严格技术教练');
    expect(result).not.toContain('态度：豆包');

    // P2 + doubao → 应加载 attitude-doubao（不加载 attitude-sensei）
    const doubaoSkills = d.selectForPhase('P2_PRACTICE_LOOP', 'doubao');
    const doubaoIds = doubaoSkills.map(s => s.meta.id);
    expect(doubaoIds).toContain('attitude-doubao');
    expect(doubaoIds).not.toContain('attitude-sensei');

    const doubaoResult = d.composePrompt('P2_PRACTICE_LOOP', 'doubao');
    expect(doubaoResult).toContain('态度：豆包');
    expect(doubaoResult).not.toContain('态度：Sensei');

    fs.rmSync(skillsDir, { recursive: true, force: true });
  });
});

describe('Sprint 14 E2E 场景 3：safety word 触发时跳过 condition 约束的 SKILL', () => {
  it('safetyWord=true → 跳过有 user.safetyWord IS_NOT true 约束的 SKILL', () => {
    const skillsDir = path.join(TEST_DIR, 's3');
    fs.mkdirSync(skillsDir, { recursive: true });

    fs.writeFileSync(path.join(skillsDir, 'sk-strict.md'), `---
id: sk-strict
estimatedTokens: 300
loadWhen:
  phases: [P3_TRAINING]
  attitudes: [doubao, yuesheng, sensei]
  conditions:
    - type: user.safetyWord
      op: IS_NOT
      value: true
---

${technicalContent('严格训练')}`);

    fs.writeFileSync(path.join(skillsDir, 'sk-relaxed.md'), `---
id: sk-relaxed
estimatedTokens: 200
loadWhen:
  phases: [P3_TRAINING]
  attitudes: [doubao, yuesheng, sensei]
---

${technicalContent('放松训练')}`);

    const d = new SkillDispatcher();
    d.load(skillsDir);

    // safetyWord=false → 加载全部 2 个
    const normal = d.selectForPhase('P3_TRAINING', 'doubao', {}, { safetyWord: false });
    expect(normal.map(s => s.meta.id).sort()).toEqual(['sk-relaxed', 'sk-strict']);

    // safetyWord=true → 仅 sk-relaxed
    const safe = d.selectForPhase('P3_TRAINING', 'doubao', {}, { safetyWord: true });
    expect(safe.map(s => s.meta.id)).toEqual(['sk-relaxed']);

    fs.rmSync(skillsDir, { recursive: true, force: true });
  });

  it('evidence.quality=low → 加载强化反馈 SKILL；=high → 不加载', () => {
    const skillsDir = path.join(TEST_DIR, 's3b');
    fs.mkdirSync(skillsDir, { recursive: true });

    fs.writeFileSync(path.join(skillsDir, 'sk-reinforce.md'), `---
id: sk-reinforce
estimatedTokens: 250
loadWhen:
  phases: [P2_PRACTICE_LOOP]
  attitudes: [doubao]
  conditions:
    - type: evidence.quality
      op: IN
      values: [low, medium]
---

${technicalContent('强化反馈')}`);

    const d = new SkillDispatcher();
    d.load(skillsDir);

    const low = d.selectForPhase('P2_PRACTICE_LOOP', 'doubao', {}, { evidenceQuality: 'low' });
    expect(low.map(s => s.meta.id)).toEqual(['sk-reinforce']);

    const high = d.selectForPhase('P2_PRACTICE_LOOP', 'doubao', {}, { evidenceQuality: 'high' });
    expect(high).toEqual([]);

    fs.rmSync(skillsDir, { recursive: true, force: true });
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
  it('完整 5 phase × 3 attitude 矩阵：每个 attitude 加载对应 attitude-*.md SKILL', () => {
    const skillsDir = path.join(TEST_DIR, 's5');
    fs.mkdirSync(skillsDir, { recursive: true });

    // 构造覆盖全 phase / attitude 的 SKILL
    // p3-strict 加 conditions 约束：仅在未触发安全词时加载
    const skills: Array<{ id: string; phase: string; attitude: string; conditionsYaml?: string }> = [
      { id: 'p0-core', phase: 'P0_INIT', attitude: 'doubao,yuesheng,sensei' },
      { id: 'p1-core', phase: 'P1_WORLD', attitude: 'doubao,yuesheng,sensei' },
      { id: 'p2-core', phase: 'P2_PRACTICE_LOOP', attitude: 'doubao,yuesheng' },
      { id: 'p2-sensei', phase: 'P2_PRACTICE_LOOP', attitude: 'sensei' },
      {
        id: 'p3-strict',
        phase: 'P3_TRAINING',
        attitude: 'doubao,yuesheng',
        conditionsYaml: `  conditions:
    - type: user.safetyWord
      op: IS_NOT
      value: true`,
      },
      { id: 'p4-review', phase: 'P4_REVIEW', attitude: 'doubao,yuesheng,sensei' },
    ];

    for (const s of skills) {
      const yaml = `---
id: ${s.id}
estimatedTokens: 100
loadWhen:
  phases: [${s.phase}]
  attitudes: [${s.attitude}]
${s.conditionsYaml ?? ''}
---

${technicalContent(s.id)}`;
      fs.writeFileSync(path.join(skillsDir, `${s.id}.md`), yaml);
    }

    // 3 个 attitude 指令 SKILL
    for (const att of ['doubao', 'yuesheng', 'sensei']) {
      const yaml = `---
id: attitude-${att}
estimatedTokens: 100
loadWhen:
  phases: [P0_INIT, P1_WORLD, P2_PRACTICE_LOOP, P3_TRAINING, P4_REVIEW]
  attitudes: [${att}]
---

# 态度：${att}
${att} 档位行为指令。`;
      fs.writeFileSync(path.join(skillsDir, `attitude-${att}.md`), yaml);
    }

    const d = new SkillDispatcher();
    d.load(skillsDir);

    const phases: Array<'P0_INIT' | 'P1_WORLD' | 'P2_PRACTICE_LOOP' | 'P3_TRAINING' | 'P4_REVIEW'> = [
      'P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW',
    ];
    const attitudes: Array<'doubao' | 'yuesheng' | 'sensei'> = ['doubao', 'yuesheng', 'sensei'];

    // 矩阵运行：每个 (phase, attitude) 都应正常返回 + 加载对应 attitude-*.md
    for (const phase of phases) {
      for (const attitude of attitudes) {
        const result = d.composePrompt(phase, attitude, {}, { evidenceQuality: 'low', safetyWord: false });
        // 验证加载了对应 attitude 的 SKILL
        expect(result).toContain(`态度：${attitude}`);
        // 不加载其他 attitude 的 SKILL
        const otherAttitudes = attitudes.filter(a => a !== attitude);
        for (const other of otherAttitudes) {
          expect(result).not.toContain(`态度：${other}`);
        }
      }
    }

    // safety word 触发：p3-strict 不应加载
    const safetyCtx = { evidenceQuality: 'low' as const, safetyWord: true };
    const safeP3 = d.selectForPhase('P3_TRAINING', 'doubao', {}, safetyCtx);
    expect(safeP3.map(s => s.meta.id)).not.toContain('p3-strict');

    fs.rmSync(skillsDir, { recursive: true, force: true });
  });
});
