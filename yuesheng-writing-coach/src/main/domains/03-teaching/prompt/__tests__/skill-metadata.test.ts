import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import {
  parseSkillFile,
  loadAllSkills,
} from '../skill-metadata';

const TEST_SKILLS_DIR = path.join(os.tmpdir(), 'test-skills-' + Date.now());
const INVALID_SKILLS_DIR = path.join(TEST_SKILLS_DIR, 'invalid-subdir');

beforeAll(() => {
  fs.mkdirSync(TEST_SKILLS_DIR, { recursive: true });
  fs.mkdirSync(INVALID_SKILLS_DIR, { recursive: true });

  fs.writeFileSync(
    path.join(TEST_SKILLS_DIR, 'core-identity.md'),
    `---
id: core-identity
estimatedTokens: 3000
loadWhen:
  phases: [P0_INIT, P1_WORLD, P2_PRACTICE_LOOP, P3_TRAINING, P4_REVIEW]
  attitudes: [doubao, yuesheng, sensei]
---

# Core Identity Content
`,
  );

  fs.writeFileSync(
    path.join(TEST_SKILLS_DIR, 'reference-drawer.md'),
    `---
id: reference-drawer
estimatedTokens: 2000
loadWhen:
  phases: [P2_PRACTICE_LOOP, P3_TRAINING, P4_REVIEW]
  attitudes: [doubao, yuesheng, sensei]
---

# Reference Drawer Content
`,
  );

  fs.writeFileSync(
    path.join(INVALID_SKILLS_DIR, 'invalid.md'),
    `# Missing frontmatter
`,
  );
});

afterAll(() => {
  fs.rmSync(TEST_SKILLS_DIR, { recursive: true, force: true });
});

describe('parseSkillFile', () => {
  it('正确解析合法 SKILL 文件', () => {
    const skill = parseSkillFile(path.join(TEST_SKILLS_DIR, 'core-identity.md'));
    expect(skill.meta.id).toBe('core-identity');
    expect(skill.meta.estimatedTokens).toBe(3000);
    expect(skill.meta.loadWhen.phases).toEqual([
      'P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW',
    ]);
    expect(skill.meta.loadWhen.attitudes).toEqual(['doubao', 'yuesheng', 'sensei']);
    expect(skill.content).toContain('# Core Identity Content');
  });

  it('YAML 缺失时抛错', () => {
    expect(() => parseSkillFile(path.join(INVALID_SKILLS_DIR, 'invalid.md')))
      .toThrow(/Missing YAML frontmatter/);
  });

  it('loadWhen 格式错误时抛错', () => {
    const badFile = path.join(TEST_SKILLS_DIR, 'bad-loadwhen.md');
    fs.writeFileSync(
      badFile,
      `---
id: bad
estimatedTokens: 100
loadWhen:
  phases: invalid
---

# Bad
`,
    );
    expect(() => parseSkillFile(badFile)).toThrow(/Invalid loadWhen format/);
    fs.unlinkSync(badFile);
  });

  it('estimatedTokens 非正整数时抛错', () => {
    const badFile = path.join(TEST_SKILLS_DIR, 'bad-tokens.md');
    fs.writeFileSync(
      badFile,
      `---
id: bad
estimatedTokens: -1
loadWhen:
  phases: [P0_INIT]
  attitudes: [doubao]
---

# Bad
`,
    );
    expect(() => parseSkillFile(badFile)).toThrow(/Invalid estimatedTokens/);
    fs.unlinkSync(badFile);
  });
});

describe('loadAllSkills', () => {
  it('加载目录下所有 .md 文件', () => {
    const skills = loadAllSkills(TEST_SKILLS_DIR);
    expect(skills.length).toBe(2);
    const ids = skills.map(s => s.meta.id).sort();
    expect(ids).toEqual(['core-identity', 'reference-drawer']);
  });

  it('目录不存在时抛错', () => {
    expect(() => loadAllSkills('/nonexistent/path'))
      .toThrow(/Directory not found/);
  });
});
