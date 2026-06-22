import { describe, it, expect } from 'vitest';
import * as path from 'path';
import { loadAllSkills, type Skill } from '../skill-metadata';

const SKILLS_DIR = path.resolve(__dirname, '../../../../../../resources/prompts/skills');

describe('SKILL 结构校验（按文件）', () => {
  const skills: Skill[] = loadAllSkills(SKILLS_DIR);
  const skillsById = new Map(skills.map(s => [s.meta.id, s]));

  it('加载到 8 个 SKILL 文件（Sprint 14-prior 拆分 core-identity）', () => {
    // Sprint 14-prior: core-identity 拆分为 core-iron-triangle + core-product-identity
    // 原 6 个 + 2 个新核心子集 = 8 个
    expect(skills.length).toBe(8);
  });

  it('core-iron-triangle 必含铁三角与回复控制（核心子集）', () => {
    // Sprint 14-prior: 铁三角 + 回复控制 → core-iron-triangle
    const s = skillsById.get('core-iron-triangle');
    expect(s).toBeDefined();
    expect(s!.meta.isCoreSubset).toBe(true);
    expect(s!.meta.parentId).toBe('core-identity');
    expect(s!.content).toContain('## 一、铁三角');
    expect(s!.content).toContain('### 1. 倾听优先');
    expect(s!.content).toContain('### 2. 教练定位');
    expect(s!.content).toContain('### 3. 找根因');
    expect(s!.content).toContain('## 二、回复控制');
  });

  it('core-product-identity 必含产品身份与底线（P2+ 加载）', () => {
    // Sprint 14-prior: 产品身份 + 底线清单 → core-product-identity
    const s = skillsById.get('core-product-identity');
    expect(s).toBeDefined();
    expect(s!.meta.isCoreSubset).toBe(true);
    expect(s!.meta.parentId).toBe('core-identity');
    expect(s!.content).toContain('## 一、产品身份与底线');
    expect(s!.content).toContain('H-❶');
    expect(s!.content).toContain('H-❷');
    expect(s!.content).toContain('H-❸');
    expect(s!.content).toContain('H-❹');
    expect(s!.content).toContain('## 二、底线清单');
  });

  it('core-identity 已转为聚合入口（DEPRECATED）', () => {
    // Sprint 14-prior: core-identity 不再承载实际内容
    const s = skillsById.get('core-identity');
    expect(s).toBeDefined();
    expect(s!.meta.isCoreSubset).toBe(false);
    expect(s!.content).toContain('DEPRECATED');
  });

  it('teaching-strategy 必含三/四/五/六章', () => {
    const s = skillsById.get('teaching-strategy');
    expect(s).toBeDefined();
    expect(s!.content).toContain('## 三、教学策略铁律');
    expect(s!.content).toContain('## 四、学员分层');
    expect(s!.content).toContain('## 五、态度档位');
    expect(s!.content).toContain('## 六、从零构建引导模式');
  });

  it('reference-drawer 必含九/十章', () => {
    const s = skillsById.get('reference-drawer');
    expect(s).toBeDefined();
    expect(s!.content).toContain('## 九、参考抽屉');
    expect(s!.content).toContain('## 十、核心信念与能力边界');
  });

  it('validation-rules 必含 V-01~V-09 全部 9 条', () => {
    const s = skillsById.get('validation-rules');
    expect(s).toBeDefined();
    for (const id of ['V-01', 'V-02', 'V-03', 'V-04', 'V-05', 'V-06', 'V-07', 'V-08', 'V-09']) {
      expect(s!.content).toContain(id);
    }
  });

  it('feedback-cognition 必含 §七 与同侪感', () => {
    const s = skillsById.get('feedback-cognition');
    expect(s).toBeDefined();
    expect(s!.content).toContain('## 七、认知反馈层');
    expect(s!.content).toContain('### 7.5 同侪感');
  });

  it('scenario-rules 必含 DP-F/G/I 与场景快速索引', () => {
    const s = skillsById.get('scenario-rules');
    expect(s).toBeDefined();
    expect(s!.content).toContain('## DP-F: 平台立场');
    expect(s!.content).toContain('## DP-G: 润色纠正');
    expect(s!.content).toContain('## DP-I: 合作伪装揭穿');
    expect(s!.content).toContain('## 场景快速索引');
  });

  it('loadWhen phases 配置符合设计（Sprint 14-prior 更新）', () => {
    // Sprint 14-prior: always 列表中 core-identity 替换为 core-iron-triangle
    const always = ['core-iron-triangle', 'teaching-strategy', 'validation-rules', 'scenario-rules'];
    const conditional = ['reference-drawer', 'feedback-cognition'];
    // core-product-identity 只在 P2+ 加载
    const p2Plus = ['core-product-identity'];

    for (const id of always) {
      const s = skillsById.get(id);
      expect(s!.meta.loadWhen.phases).toEqual([
        'P0_INIT', 'P1_WORLD', 'P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW',
      ]);
    }
    for (const id of conditional) {
      const s = skillsById.get(id);
      expect(s!.meta.loadWhen.phases).toEqual(['P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW']);
    }
    for (const id of p2Plus) {
      const s = skillsById.get(id);
      expect(s!.meta.loadWhen.phases).toEqual(['P2_PRACTICE_LOOP', 'P3_TRAINING', 'P4_REVIEW']);
    }
  });
});
