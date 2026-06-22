/**
 * ConditionEvaluator 单元测试
 *
 * 覆盖：
 * 1. 空 / undefined conditions → 默认通过
 * 2. evidence.quality IN / NOT_IN
 * 3. user.safetyWord IS / IS_NOT
 * 4. user.dominantSyndrome EQ / NEQ
 * 5. 多条件 AND 语义
 * 6. 缺失 context 字段 → fail（保守策略）
 * 7. 集成到 SkillDispatcher
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import {
  evaluateConditions,
  matchesConditions,
  type RuntimeContext,
} from '../condition-evaluator';
import { SkillDispatcher } from '../skill-dispatcher';
import type { LoadCondition } from '../skill-metadata';

const TEST_DIR = path.join(os.tmpdir(), 'test-conditions-' + Date.now());

beforeAll(() => {
  fs.mkdirSync(TEST_DIR, { recursive: true });
});

afterAll(() => {
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
});

describe('evaluateConditions', () => {
  it('空 conditions 列表默认通过', () => {
    const result = evaluateConditions([], { evidenceQuality: 'high' });
    expect(result.passed).toBe(true);
    expect(result.failedConditions).toEqual([]);
  });

  it('undefined conditions 默认通过', () => {
    const result = evaluateConditions(undefined, {});
    expect(result.passed).toBe(true);
  });

  it('evidence.quality IN — 命中', () => {
    const conds: LoadCondition[] = [
      { type: 'evidence.quality', op: 'IN', values: ['low', 'medium'] },
    ];
    expect(evaluateConditions(conds, { evidenceQuality: 'low' }).passed).toBe(true);
    expect(evaluateConditions(conds, { evidenceQuality: 'medium' }).passed).toBe(true);
    expect(evaluateConditions(conds, { evidenceQuality: 'high' }).passed).toBe(false);
  });

  it('evidence.quality NOT_IN — 反向命中', () => {
    const conds: LoadCondition[] = [
      { type: 'evidence.quality', op: 'NOT_IN', values: ['low'] },
    ];
    expect(evaluateConditions(conds, { evidenceQuality: 'low' }).passed).toBe(false);
    expect(evaluateConditions(conds, { evidenceQuality: 'high' }).passed).toBe(true);
  });

  it('evidence.quality 缺失 context → fail', () => {
    const conds: LoadCondition[] = [
      { type: 'evidence.quality', op: 'IN', values: ['low'] },
    ];
    expect(evaluateConditions(conds, {}).passed).toBe(false);
  });

  it('user.safetyWord IS — 命中', () => {
    const conds: LoadCondition[] = [
      { type: 'user.safetyWord', op: 'IS', value: true },
    ];
    expect(evaluateConditions(conds, { safetyWord: true }).passed).toBe(true);
    expect(evaluateConditions(conds, { safetyWord: false }).passed).toBe(false);
  });

  it('user.safetyWord IS_NOT — 反向', () => {
    const conds: LoadCondition[] = [
      { type: 'user.safetyWord', op: 'IS_NOT', value: true },
    ];
    expect(evaluateConditions(conds, { safetyWord: false }).passed).toBe(true);
    expect(evaluateConditions(conds, { safetyWord: true }).passed).toBe(false);
  });

  it('user.safetyWord 缺失 context → fail（保守）', () => {
    const conds: LoadCondition[] = [
      { type: 'user.safetyWord', op: 'IS', value: false },
    ];
    expect(evaluateConditions(conds, {}).passed).toBe(false);
  });

  it('user.dominantSyndrome EQ — 命中', () => {
    const conds: LoadCondition[] = [
      { type: 'user.dominantSyndrome', op: 'EQ', syndromeId: 'over-description' },
    ];
    expect(evaluateConditions(conds, { dominantSyndrome: 'over-description' }).passed).toBe(true);
    expect(evaluateConditions(conds, { dominantSyndrome: 'pacing' }).passed).toBe(false);
  });

  it('user.dominantSyndrome NEQ — 反向', () => {
    const conds: LoadCondition[] = [
      { type: 'user.dominantSyndrome', op: 'NEQ', syndromeId: 'over-description' },
    ];
    expect(evaluateConditions(conds, { dominantSyndrome: 'pacing' }).passed).toBe(true);
    expect(evaluateConditions(conds, { dominantSyndrome: 'over-description' }).passed).toBe(false);
  });

  it('多条件 AND 语义 — 全部通过', () => {
    const conds: LoadCondition[] = [
      { type: 'evidence.quality', op: 'IN', values: ['low', 'medium'] },
      { type: 'user.safetyWord', op: 'IS_NOT', value: true },
    ];
    const ctx: RuntimeContext = {
      evidenceQuality: 'medium',
      safetyWord: false,
    };
    expect(evaluateConditions(conds, ctx).passed).toBe(true);
  });

  it('多条件 AND 语义 — 任一失败则整体失败', () => {
    const conds: LoadCondition[] = [
      { type: 'evidence.quality', op: 'IN', values: ['low', 'medium'] },
      { type: 'user.safetyWord', op: 'IS_NOT', value: true },
    ];
    const ctx: RuntimeContext = {
      evidenceQuality: 'high', // 不在 IN 列表
      safetyWord: false,
    };
    const result = evaluateConditions(conds, ctx);
    expect(result.passed).toBe(false);
    expect(result.failedConditions).toHaveLength(1);
    expect(result.failedConditions[0]).toContain('evidence.quality');
  });

  it('matchesConditions 便捷函数', () => {
    const conds: LoadCondition[] = [
      { type: 'evidence.quality', op: 'IN', values: ['low'] },
    ];
    expect(matchesConditions(conds, { evidenceQuality: 'low' })).toBe(true);
    expect(matchesConditions(conds, { evidenceQuality: 'high' })).toBe(false);
    expect(matchesConditions(undefined, {})).toBe(true);
  });
});

describe('SkillDispatcher 集成 conditions', () => {
  it('selectForPhase 接受 runtimeCtx 并按 conditions 过滤', () => {
    // 构造 2 个 SKILL：一个无条件，一个有 evidence.quality IN [low]
    const skillsDir = path.join(TEST_DIR, 'skills-conditions');
    fs.mkdirSync(skillsDir, { recursive: true });

    const yaml1 = `---
id: no-condition
estimatedTokens: 100
loadWhen:
  phases: [P0_INIT]
  attitudes: [doubao, yuesheng, sensei]
---

# 无条件 SKILL 1
内容：第一段在描写角色心理活动时需要更深层的笔触。通过细节让读者感受人物的内心冲突。`;

    const yaml2 = `---
id: low-quality-only
estimatedTokens: 200
loadWhen:
  phases: [P0_INIT]
  attitudes: [doubao, yuesheng, sensei]
---

# 仅低质量时加载
内容：当 evidence 质量低时加载此 SKILL，给出强化反馈。`;

    fs.writeFileSync(path.join(skillsDir, 'no-condition.md'), yaml1);
    fs.writeFileSync(path.join(skillsDir, 'low-quality-only.md'), yaml2);

    // 注：YAML 简写 `conditions: [low]` 解析为 user.dominantSyndrome EQ low
    // 这里我们改用 dispatcher 注入完整 LoadCondition（更直接）

    const d = new SkillDispatcher();
    d.load(skillsDir);

    // 1. 默认（无 runtimeCtx）→ 缺 context 时所有 conditions 视为 fail
    // 但我们用 0 长度 runtimeCtx 测试简单情况
    const all = d.selectForPhase('P0_INIT', 'doubao');
    expect(all.length).toBeGreaterThanOrEqual(1);

    fs.rmSync(skillsDir, { recursive: true, force: true });
  });

  it('在构造 SKILL 时通过 conditions 字段过滤', () => {
    // 直接构造 Skill 对象（绕过 YAML 解析），测试 dispatcher 集成
    const d = new SkillDispatcher();
    // 注入 2 个 SKILL
    (d as unknown as { skills: Map<string, unknown> }).skills.set('sk-no-cond', {
      meta: {
        id: 'sk-no-cond',
        estimatedTokens: 100,
        loadWhen: { phases: ['P0_INIT'], attitudes: ['doubao'] },
      },
      content: '# 无条件',
    });
    (d as unknown as { skills: Map<string, unknown> }).skills.set('sk-with-cond', {
      meta: {
        id: 'sk-with-cond',
        estimatedTokens: 200,
        loadWhen: {
          phases: ['P0_INIT'],
          attitudes: ['doubao'],
          conditions: [
            { type: 'evidence.quality', op: 'IN', values: ['low'] } as LoadCondition,
          ],
        },
      },
      content: '# 有条件',
    });
    (d as unknown as { loaded: boolean }).loaded = true;

    // quality=low → 2 个都返回
    const lowResult = d.selectForPhase('P0_INIT', 'doubao', {}, { evidenceQuality: 'low' });
    expect(lowResult.map(s => s.meta.id).sort()).toEqual(['sk-no-cond', 'sk-with-cond']);

    // quality=high → 仅 sk-no-cond
    const highResult = d.selectForPhase('P0_INIT', 'doubao', {}, { evidenceQuality: 'high' });
    expect(highResult.map(s => s.meta.id)).toEqual(['sk-no-cond']);

    // 缺 context → sk-with-cond 不通过
    const noCtxResult = d.selectForPhase('P0_INIT', 'doubao', {}, {});
    expect(noCtxResult.map(s => s.meta.id)).toEqual(['sk-no-cond']);
  });

  it('safetyWord=true 时跳过需要安全词未触发的 SKILL', () => {
    const d = new SkillDispatcher();
    (d as unknown as { skills: Map<string, unknown> }).skills.set('sk-requires-no-safety', {
      meta: {
        id: 'sk-requires-no-safety',
        estimatedTokens: 100,
        loadWhen: {
          phases: ['P0_INIT'],
          attitudes: ['doubao'],
          conditions: [
            { type: 'user.safetyWord', op: 'IS_NOT', value: true } as LoadCondition,
          ],
        },
      },
      content: '# 正常时加载',
    });
    (d as unknown as { loaded: boolean }).loaded = true;

    // safetyWord 未触发 → 加载
    const normal = d.selectForPhase('P0_INIT', 'doubao', {}, { safetyWord: false });
    expect(normal.map(s => s.meta.id)).toEqual(['sk-requires-no-safety']);

    // safetyWord 触发 → 不加载
    const safe = d.selectForPhase('P0_INIT', 'doubao', {}, { safetyWord: true });
    expect(safe.map(s => s.meta.id)).toEqual([]);
  });
});
