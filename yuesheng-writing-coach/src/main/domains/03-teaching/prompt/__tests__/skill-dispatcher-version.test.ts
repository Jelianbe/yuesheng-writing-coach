/**
 * SkillDispatcher 版本过滤测试 — Sprint 20 A-2 桥接真实实现
 *
 * 覆盖：
 * 1. 不传 promptVersion → 向后兼容,行为不变
 * 2. 传 promptVersion → 只返回 SkillRegistry.compatibleWith(version) 命中的 skill
 * 3. 未知 version → 全部不命中,返回空
 * 4. setRegistry 注入测试桩
 * 5. skill 在 registry 中无元数据 → 视为兼容（向后兼容）
 * 6. 元数据声明空数组 → 视为不兼容（契约硬要求）
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { SkillDispatcher } from '../skill-dispatcher';
import { SkillRegistry } from '../../conversation/skill-registry';

const TEST_DIR = path.join(os.tmpdir(), 'test-sd-version-' + Date.now());

/** 写一个带 frontmatter（含 compatiblePromptVersions）的 skill */
function writeSkill(
  id: string,
  estimatedTokens: number,
  compatiblePromptVersions: string[],
  phases: string[] = ['P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'],
): void {
  const filePath = path.join(TEST_DIR, `${id}.md`);
  fs.writeFileSync(
    filePath,
    `---
id: ${id}
estimatedTokens: ${estimatedTokens}
loadWhen:
  phases: [${phases.join(', ')}]
  attitudes: [doubao, yuesheng, sensei]
compatiblePromptVersions: [${compatiblePromptVersions.join(', ')}]
---

# ${id} content
`,
  );
}

beforeAll(() => {
  fs.mkdirSync(TEST_DIR, { recursive: true });

  // 4 个 always-required skill,只声明 v5.0.0 兼容
  writeSkill('core-identity', 1500, ['v5.0.0']);
  writeSkill('teaching-strategy', 2000, ['v5.0.0']);
  writeSkill('scenario-rules', 1100, ['v5.0.0']);
  writeSkill('validation-rules', 1700, ['v5.0.0']);

  // feedback-cognition 同时兼容 v5.0.0 和 v6.0.0
  writeSkill('feedback-cognition', 900, ['v5.0.0', 'v6.0.0']);
});

afterAll(() => {
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
});

describe('SkillDispatcher 版本过滤 (Sprint 20 A-2)', () => {
  it('不传 promptVersion:行为不变(向后兼容),P0_INIT 命中 5 个 skill', () => {
    const d = new SkillDispatcher();
    d.load(TEST_DIR);
    const skills = d.selectForPhase('P0_INIT', 'doubao');
    const ids = skills.map(s => s.meta.id).sort();
    expect(ids).toEqual([
      'core-identity',
      'feedback-cognition',
      'scenario-rules',
      'teaching-strategy',
      'validation-rules',
    ]);
  });

  it('传 promptVersion=v5.0.0:命中 5 个兼容 v5.0.0 的 skill', () => {
    const d = new SkillDispatcher();
    d.load(TEST_DIR);
    const skills = d.selectForPhase('P0_INIT', 'doubao', { promptVersion: 'v5.0.0' });
    const ids = skills.map(s => s.meta.id).sort();
    expect(ids).toEqual([
      'core-identity',
      'feedback-cognition',
      'scenario-rules',
      'teaching-strategy',
      'validation-rules',
    ]);
  });

  it('传 promptVersion=v6.0.0:仅 feedback-cognition 兼容', () => {
    const d = new SkillDispatcher();
    d.load(TEST_DIR);
    const skills = d.selectForPhase('P0_INIT', 'doubao', { promptVersion: 'v6.0.0' });
    const ids = skills.map(s => s.meta.id);
    expect(ids).toEqual(['feedback-cognition']);
  });

  it('传未知 promptVersion=v999:全部不命中(空数组)', () => {
    const d = new SkillDispatcher();
    d.load(TEST_DIR);
    const skills = d.selectForPhase('P0_INIT', 'doubao', { promptVersion: 'v999-not-exist' });
    expect(skills).toEqual([]);
  });

  it('getRegistry() 返回自动创建的默认 registry', () => {
    const d = new SkillDispatcher();
    d.load(TEST_DIR);
    const registry = d.getRegistry();
    expect(registry).not.toBeNull();
    expect(registry).toBeInstanceOf(SkillRegistry);
    expect(registry!.stats().total).toBe(5);
  });

  it('setRegistry 注入测试桩:定制过滤规则', () => {
    // 构造一个隔离目录,放 5 个 skill,均只声明 vCustom 兼容
    const customDir = path.join(os.tmpdir(), 'test-custom-registry-' + Date.now());
    fs.mkdirSync(customDir, { recursive: true });
    try {
      const skills = [
        ['core-identity', 1500],
        ['teaching-strategy', 2000],
        ['scenario-rules', 1100],
        ['validation-rules', 1700],
        ['feedback-cognition', 900],
      ] as const;
      for (const [id, tokens] of skills) {
        fs.writeFileSync(
          path.join(customDir, `${id}.md`),
          `---
id: ${id}
estimatedTokens: ${tokens}
loadWhen:
  phases: [P0_INIT, P1_WORLD, P2_PRACTICE_LOOP, P3_TRAINING, P4_REVIEW]
  attitudes: [doubao, yuesheng, sensei]
compatiblePromptVersions: [vCustom]
---

# ${id}
`,
        );
      }
      const customRegistry = new SkillRegistry(customDir);
      // 验证:customRegistry 只承认 vCustom 兼容
      expect(customRegistry.compatibleWith('vCustom')).toHaveLength(5);
      expect(customRegistry.compatibleWith('v5.0.0')).toHaveLength(0);

      // 用 TEST_DIR 的 dispatcher 加载,再注入 custom registry
      const d = new SkillDispatcher();
      d.setRegistry(customRegistry);
      d.load(TEST_DIR);

      // version=vCustom → 命中 5 个(customRegistry 全部承认 vCustom)
      const vCustomSkills = d.selectForPhase('P0_INIT', 'doubao', { promptVersion: 'vCustom' });
      expect(vCustomSkills.map(s => s.meta.id).sort()).toEqual([
        'core-identity',
        'feedback-cognition',
        'scenario-rules',
        'teaching-strategy',
        'validation-rules',
      ]);

      // version=v5.0.0 → 全部不命中(customRegistry 不承认 v5.0.0)
      const v500Skills = d.selectForPhase('P0_INIT', 'doubao', { promptVersion: 'v5.0.0' });
      expect(v500Skills).toEqual([]);
    } finally {
      fs.rmSync(customDir, { recursive: true, force: true });
    }
  });

  it('setRegistry 在 load() 之后调用 → 抛错', () => {
    const d = new SkillDispatcher();
    d.load(TEST_DIR);
    expect(() => d.setRegistry(new SkillRegistry(TEST_DIR))).toThrow(/必须在 load\(\) 之前/);
  });

  it('skill 在 registry 中无元数据 → 视为兼容(向后兼容)', () => {
    // 构造一个不存在的 skill id
    const customDir = path.join(os.tmpdir(), 'test-empty-registry-' + Date.now());
    fs.mkdirSync(customDir, { recursive: true });
    try {
      // 空目录,registry 无任何元数据
      const emptyRegistry = new SkillRegistry(customDir);

      const d = new SkillDispatcher();
      d.setRegistry(emptyRegistry);
      d.load(TEST_DIR);

      // 传 version → registry 找不到元数据 → 全部通过
      const skills = d.selectForPhase('P0_INIT', 'doubao', { promptVersion: 'v5.0.0' });
      expect(skills).toHaveLength(5);
    } finally {
      fs.rmSync(customDir, { recursive: true, force: true });
    }
  });

  it('元数据声明 compatiblePromptVersions 为空数组 → 视为不兼容', () => {
    // 写一个 skill 声明 compatiblePromptVersions: []（显式空）
    const filePath = path.join(TEST_DIR, 'broken-skill.md');
    fs.writeFileSync(
      filePath,
      `---
id: broken-skill
estimatedTokens: 100
loadWhen:
  phases: [P0_INIT]
  attitudes: [doubao]
compatiblePromptVersions: []
---

# broken content
`,
    );
    try {
      const d = new SkillDispatcher();
      d.load(TEST_DIR);

      // 不传 version → broken-skill 仍会被加载
      const all = d.selectForPhase('P0_INIT', 'doubao');
      expect(all.map(s => s.meta.id)).toContain('broken-skill');

      // 传 version → broken-skill 被过滤
      const filtered = d.selectForPhase('P0_INIT', 'doubao', { promptVersion: 'v5.0.0' });
      expect(filtered.map(s => s.meta.id)).not.toContain('broken-skill');
    } finally {
      fs.rmSync(filePath, { force: true });
    }
  });

  it('version 过滤与 phase/attitude 过滤 AND 组合', () => {
    const d = new SkillDispatcher();
    d.load(TEST_DIR);
    // 选 P0_INIT doubao,version=v6.0.0 → 仅 feedback-cognition(P0_INIT 命中 + doubao 命中 + v6.0.0 兼容)
    const skills = d.selectForPhase('P0_INIT', 'doubao', { promptVersion: 'v6.0.0' });
    expect(skills).toHaveLength(1);
    expect(skills[0].meta.id).toBe('feedback-cognition');
    // 三档 attitude 都应一致
    expect(d.selectForPhase('P0_INIT', 'yuesheng', { promptVersion: 'v6.0.0' })).toHaveLength(1);
    expect(d.selectForPhase('P0_INIT', 'sensei', { promptVersion: 'v6.0.0' })).toHaveLength(1);
  });
});
