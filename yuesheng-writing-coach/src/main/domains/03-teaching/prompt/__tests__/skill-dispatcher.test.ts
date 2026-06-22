import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import { SkillDispatcher } from '../skill-dispatcher';

const TEST_SKILLS_DIR = path.join(os.tmpdir(), 'test-dispatcher-' + Date.now());

beforeAll(() => {
  fs.mkdirSync(TEST_SKILLS_DIR, { recursive: true });

  const alwaysSkills = [
    ['core-identity', 3000],
    ['teaching-strategy', 8000],
    ['validation-rules', 5000],
    ['scenario-rules', 4000],
  ];
  for (const [id, tokens] of alwaysSkills) {
    fs.writeFileSync(
      path.join(TEST_SKILLS_DIR, `${id}.md`),
      `---
id: ${id}
estimatedTokens: ${tokens}
loadWhen:
  phases: [P0_INIT, P1_WORLD, P2_PRACTICE_LOOP, P3_TRAINING, P4_REVIEW]
  attitudes: [doubao, yuesheng, sensei]
---

# ${id} content
`,
    );
  }

  const conditionalSkills = [
    ['reference-drawer', 2000],
    ['feedback-cognition', 3000],
  ];
  for (const [id, tokens] of conditionalSkills) {
    fs.writeFileSync(
      path.join(TEST_SKILLS_DIR, `${id}.md`),
      `---
id: ${id}
estimatedTokens: ${tokens}
loadWhen:
  phases: [P2_PRACTICE_LOOP, P3_TRAINING, P4_REVIEW]
  attitudes: [doubao, yuesheng, sensei]
---

# ${id} content
`,
    );
  }
});

afterAll(() => {
  fs.rmSync(TEST_SKILLS_DIR, { recursive: true, force: true });
});

describe('SkillDispatcher', () => {
  it('P0_INIT 加载 4 个必加载 SKILL（20K tokens）', () => {
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    const skills = d.selectForPhase('P0_INIT', 'doubao');
    const ids = skills.map(s => s.meta.id).sort();
    expect(ids).toEqual(['core-identity', 'scenario-rules', 'teaching-strategy', 'validation-rules']);
    expect(d.estimateTokens('P0_INIT', 'doubao')).toBe(20000);
  });

  it('P2_PRACTICE_LOOP 加载全部 6 个 SKILL（25K tokens）', () => {
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    const skills = d.selectForPhase('P2_PRACTICE_LOOP', 'doubao');
    expect(skills.length).toBe(6);
    expect(d.estimateTokens('P2_PRACTICE_LOOP', 'doubao')).toBe(25000);
  });

  it('5 种 phase 组合覆盖预期 SKILL 集合', () => {
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    const phases = ['P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW'] as const;
    for (const phase of phases) {
      const skills = d.selectForPhase(phase, 'yuesheng');
      const tokens = d.estimateTokens(phase, 'yuesheng');
      if (phase === 'P0_INIT' || phase === 'P1_WORLD') {
        expect(skills.length).toBe(4);
        expect(tokens).toBe(20000);
      } else {
        expect(skills.length).toBe(6);
        expect(tokens).toBe(25000);
      }
    }
  });

  it('Sprint 13 简化：attitude 维度不影响加载结果', () => {
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    const doubaoCount = d.selectForPhase('P0_INIT', 'doubao').length;
    const yueshengCount = d.selectForPhase('P0_INIT', 'yuesheng').length;
    const senseiCount = d.selectForPhase('P0_INIT', 'sensei').length;
    expect(doubaoCount).toBe(yueshengCount);
    expect(yueshengCount).toBe(senseiCount);
  });

  it('composePrompt 拼接所有命中 SKILL', () => {
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    const prompt = d.composePrompt('P0_INIT', 'doubao');
    expect(prompt).toContain('# core-identity content');
    expect(prompt).toContain('# teaching-strategy content');
    expect(prompt).toContain('# validation-rules content');
    expect(prompt).toContain('# scenario-rules content');
    expect(prompt).toContain('\n\n---\n\n');
  });

  it('load() 前调用 selectForPhase 抛错', () => {
    const d = new SkillDispatcher();
    expect(() => d.selectForPhase('P0_INIT', 'doubao'))
      .toThrow(/Not loaded/);
  });

  it('clear() 后可重新加载', () => {
    const d = new SkillDispatcher();
    d.load(TEST_SKILLS_DIR);
    expect(d.getAllSkills().length).toBe(6);
    d.clear();
    expect(d.getAllSkills().length).toBe(0);
    d.load(TEST_SKILLS_DIR);
    expect(d.getAllSkills().length).toBe(6);
  });
});
