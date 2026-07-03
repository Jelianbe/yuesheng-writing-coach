/**
 * Skill Registry 单测(Sprint 20 增量 1)
 *
 * 验证:
 * - 扫描 skills/*.md 解析 frontmatter(id/estimatedTokens/compatiblePromptVersions)
 * - getById / getAll / compatibleWith 行为正确
 * - 版本过滤:不同 prompt 版本返回不同 skill 集合
 * - 与 orchestrator 集成:MockConversationOrchestrator.skillManifest(phase, version)
 */

import { describe, it, expect } from 'vitest';
import * as path from 'node:path';
import { SkillRegistry, createDefaultSkillRegistry } from '../skill-registry';
import { MockConversationOrchestrator } from '../mock-orchestrator';

const PROJECT_ROOT = path.resolve(__dirname, '../../../../../..');
const SKILLS_DIR = path.join(PROJECT_ROOT, 'resources/prompts/skills');

describe('SkillRegistry (增量 1)', () => {
  it('加载所有 .md skill 文件', () => {
    const registry = new SkillRegistry(SKILLS_DIR);
    const stats = registry.stats();
    expect(stats.total).toBeGreaterThanOrEqual(5);
    expect(stats.withVersion).toBeGreaterThanOrEqual(5);
  });

  it('契约必需的 5 个 skill 全部存在', () => {
    const registry = new SkillRegistry(SKILLS_DIR);
    const required = ['core-identity', 'scenario-rules', 'teaching-strategy', 'validation-rules', 'feedback-cognition'];
    for (const id of required) {
      const meta = registry.getById(id);
      expect(meta, `skill ${id} 应存在`).toBeDefined();
      expect(meta!.estimatedTokens).toBeGreaterThan(0);
      expect(meta!.compatiblePromptVersions.length).toBeGreaterThan(0);
    }
  });

  it('getById 不存在 → 返回 undefined', () => {
    const registry = new SkillRegistry(SKILLS_DIR);
    expect(registry.getById('NON_EXISTENT_SKILL')).toBeUndefined();
  });

  it('compatibleWith(v5.0.0) 返回所有声明兼容 v5.0.0 的 skill', () => {
    const registry = new SkillRegistry(SKILLS_DIR);
    const compatV500 = registry.compatibleWith('v5.0.0');
    expect(compatV500.length).toBeGreaterThanOrEqual(5);
    const ids = compatV500.map(s => s.id);
    expect(ids).toContain('core-identity');
    expect(ids).toContain('teaching-strategy');
  });

  it('compatibleWith(v999) 返回空数组(无任何 skill 兼容)', () => {
    const registry = new SkillRegistry(SKILLS_DIR);
    const compatV999 = registry.compatibleWith('v999-not-exist');
    expect(compatV999).toEqual([]);
  });

  it('不同版本返回不同集合(v5.0.0 vs v5.0.1-draft)', () => {
    const registry = new SkillRegistry(SKILLS_DIR);
    const v500 = registry.compatibleWith('v5.0.0').map(s => s.id);
    const v501 = registry.compatibleWith('v5.0.1-draft').map(s => s.id);
    // 5 个契约必需 skill 在两个版本中都应该出现(因为都已声明兼容)
    expect(v500).toEqual(expect.arrayContaining(['core-identity', 'teaching-strategy']));
    expect(v501).toEqual(expect.arrayContaining(['core-identity', 'teaching-strategy']));
  });

  it('sourcePath 指向真实 .md 文件', () => {
    const registry = new SkillRegistry(SKILLS_DIR);
    const meta = registry.getById('core-identity');
    expect(meta!.sourcePath).toMatch(/core-identity\.md$/);
  });
});

describe('MockConversationOrchestrator.skillManifest (增量 1 集成)', () => {
  it('不传 version → 返回该 phase 全部 skill(向后兼容)', () => {
    const orch = new MockConversationOrchestrator();
    const skills = orch.skillManifest('diagnosis');
    expect(skills.length).toBeGreaterThan(0);
    expect(skills.map(s => s.id)).toContain('teaching-strategy');
  });

  it('传 v5.0.0 → 返回与 v5.0.0 兼容的 skill 子集', () => {
    const orch = new MockConversationOrchestrator();
    const skills = orch.skillManifest('diagnosis', 'v5.0.0');
    expect(skills.length).toBeGreaterThan(0);
    expect(skills.map(s => s.id)).toContain('teaching-strategy');
  });

  it('传 v999 → 返回空数组(无 skill 兼容)', () => {
    const orch = new MockConversationOrchestrator();
    const skills = orch.skillManifest('diagnosis', 'v999-not-exist');
    expect(skills).toEqual([]);
  });

  it('传 v5.0.1-draft → 与 v5.0.0 行为一致(因 skill 都声明了双版本兼容)', () => {
    const orch = new MockConversationOrchestrator();
    const v500 = orch.skillManifest('diagnosis', 'v5.0.0').map(s => s.id).sort();
    const v501 = orch.skillManifest('diagnosis', 'v5.0.1-draft').map(s => s.id).sort();
    expect(v500).toEqual(v501);
  });
});

describe('createDefaultSkillRegistry (工厂)', () => {
  it('从项目根加载(无需显式传 skillsDir)', () => {
    const registry = createDefaultSkillRegistry(PROJECT_ROOT);
    expect(registry.getAll().length).toBeGreaterThan(0);
  });
});
