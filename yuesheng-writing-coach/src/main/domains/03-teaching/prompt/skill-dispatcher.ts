/**
 * Skill Dispatcher — 按 phase + attitude 选 SKILL 组合
 *
 * 职责：
 * 1. 加载所有 SKILL 文件
 * 2. 按 (phase, attitude) 选 SKILL 集合
 * 3. 拼接为最终 prompt
 * 4. 估算总 token
 *
 * 设计依据：Sprint 13 设计文档 §五
 * 简化：Sprint 13 实质做 phase 维度 5 种组合；attitude 接口预留但不实质过滤
 * 升级：方向 C 时启用 attitude 维度过滤 + conditions 条件
 */

import { loadAllSkills, type Skill, type TeachingPhase, type AttitudeLevel } from './skill-metadata';

export class SkillDispatcher {
  private skills: Map<string, Skill> = new Map();
  private loaded: boolean = false;

  /**
   * 加载所有 SKILL 文件（首次调用时）
   * @param skillsDir skills 目录绝对路径
   */
  load(skillsDir: string): void {
    if (this.loaded) return;

    const skills = loadAllSkills(skillsDir);
    for (const skill of skills) {
      this.skills.set(skill.meta.id, skill);
    }
    this.loaded = true;
  }

  /**
   * 按 phase + attitude 选 SKILL
   * @param phase 当前教学阶段
   * @param attitude 当前态度档位（Sprint 13 不实质过滤，接口预留）
   * @returns 命中的 SKILL 数组
   */
  selectForPhase(phase: TeachingPhase, attitude: AttitudeLevel): Skill[] {
    if (!this.loaded) {
      throw new Error('[SkillDispatcher] Not loaded. Call load() first.');
    }

    return [...this.skills.values()].filter(skill => {
      const phaseMatch = skill.meta.loadWhen.phases.includes(phase);
      // Sprint 13 简化：attitude 不过滤（接口预留，C 时启用）
      const attitudeMatch = skill.meta.loadWhen.attitudes.includes(attitude);
      return phaseMatch && attitudeMatch;
    });
  }

  /**
   * 拼接 SKILL 为 prompt 文本
   */
  composePrompt(phase: TeachingPhase, attitude: AttitudeLevel): string {
    const skills = this.selectForPhase(phase, attitude);
    return skills.map(s => s.content).join('\n\n---\n\n');
  }

  /**
   * 估算总 token 数
   */
  estimateTokens(phase: TeachingPhase, attitude: AttitudeLevel): number {
    const skills = this.selectForPhase(phase, attitude);
    return skills.reduce((sum, s) => sum + s.meta.estimatedTokens, 0);
  }

  /** 获取所有已加载的 SKILL（测试用） */
  getAllSkills(): Skill[] {
    return [...this.skills.values()];
  }

  /** 清除缓存（用于测试或热重载） */
  clear(): void {
    this.skills.clear();
    this.loaded = false;
  }
}
