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
 * Sprint 14-prior 升级（解决 D-DEBT-11）：
 * - 新增 SelectOptions 支持 coreSubsetOnly / maxTokens 过滤
 * - composePrompt 接受预算参数（用于体积优化）
 *
 * 简化：Sprint 13 实质做 phase 维度 5 种组合；attitude 接口预留但不实质过滤
 * 升级：方向 C 时启用 attitude 维度过滤 + conditions 条件
 */

import { loadAllSkills, type Skill, type TeachingPhase, type AttitudeLevel } from './skill-metadata';
import { assertSkillGraphValid } from './skill-graph';
import { AttitudeFilter } from './attitude-filter';
import { evaluateConditions, type RuntimeContext } from './condition-evaluator';
import { truncateChapterContent } from './truncation';

/** Sprint 14-prior 新增：选择选项 */
export interface SelectOptions {
  /** 只选择 isCoreSubset=true 的 SKILL（解决 D-DEBT-11 体积膨胀） */
  coreSubsetOnly?: boolean;
  /** 最大 token 预算（超出会按 tokenPriority 截断） */
  maxTokens?: number;
  /** Sprint 14 T14-6: 单个 SKILL content 最大字符数（超出用 truncation.ts 截断） */
  maxCharsPerSkill?: number;
}

export class SkillDispatcher {
  private skills: Map<string, Skill> = new Map();
  private loaded: boolean = false;
  /** Sprint 14 T14-4: attitude 过滤注入槽（默认无过滤） */
  private attitudeFilter: AttitudeFilter | null = null;

  /**
   * 加载所有 SKILL 文件（首次调用时）
   * Sprint 14 升级：加载后调用 assertSkillGraphValid 启动时 fail-fast
   * @param skillsDir skills 目录绝对路径
   */
  load(skillsDir: string): void {
    if (this.loaded) return;

    const skills = loadAllSkills(skillsDir);
    // Sprint 14 T14-3: 启动时校验依赖图（循环 + 缺失）
    assertSkillGraphValid(skills);
    for (const skill of skills) {
      this.skills.set(skill.meta.id, skill);
    }
    this.loaded = true;
  }

  /**
   * 按 phase + attitude + options + runtimeContext 选 SKILL
   * @param phase 当前教学阶段
   * @param attitude 当前态度档位（Sprint 13 不实质过滤，接口预留）
   * @param options 过滤选项（coreSubsetOnly / maxTokens）
   * @param runtimeCtx 运行时上下文（用于 conditions 评估，T14-5 新增）
   * @returns 命中的 SKILL 数组
   */
  selectForPhase(
    phase: TeachingPhase,
    attitude: AttitudeLevel,
    options: SelectOptions = {},
    runtimeCtx: RuntimeContext = {},
  ): Skill[] {
    if (!this.loaded) {
      throw new Error('[SkillDispatcher] Not loaded. Call load() first.');
    }

    const matched = [...this.skills.values()].filter(skill => {
      const phaseMatch = skill.meta.loadWhen.phases.includes(phase);
      // Sprint 13 简化：attitude 不过滤（接口预留，C 时启用）
      const attitudeMatch = skill.meta.loadWhen.attitudes.includes(attitude);
      // Sprint 14-prior: coreSubset 过滤（解决 D-DEBT-11）
      const subsetMatch = options.coreSubsetOnly ? skill.meta.isCoreSubset === true : true;
      // Sprint 14 T14-5: conditions 评估（AND 语义）
      const conditionsMatch = evaluateConditions(
        skill.meta.loadWhen.conditions,
        runtimeCtx,
      ).passed;
      return phaseMatch && attitudeMatch && subsetMatch && conditionsMatch;
    });

    // Sprint 14-prior: 按 tokenPriority 截断
    if (options.maxTokens !== undefined && options.maxTokens > 0) {
      return this.truncateByPriority(matched, options.maxTokens);
    }

    return matched;
  }

  /**
   * 按 tokenPriority 截断 SKILL 列表（保留高优先级）
   * Sprint 14 T14-6: 同优先级时按 estimatedTokens 升序优先（小优先），保证不被大 SKILL 挤出
   * @internal
   */
  private truncateByPriority(skills: Skill[], maxTokens: number): Skill[] {
    if (skills.length === 0) return skills;

    // 按 (tokenPriority 降序, estimatedTokens 升序) 排序
    // 高优先级在前；同优先级时小 SKILL 优先（避免大 SKILL 占用预算）
    const sorted = [...skills].sort((a, b) => {
      const pa = a.meta.tokenPriority ?? 5;
      const pb = b.meta.tokenPriority ?? 5;
      if (pa !== pb) return pb - pa;
      // size tiebreak：estimatedTokens 升序
      return a.meta.estimatedTokens - b.meta.estimatedTokens;
    });

    const result: Skill[] = [];
    let total = 0;
    for (const skill of sorted) {
      const cost = skill.meta.estimatedTokens;
      if (total + cost <= maxTokens) {
        result.push(skill);
        total += cost;
      }
    }
    return result;
  }

  /**
   * 对单 SKILL content 截断（Sprint 14 T14-6 集成 truncation.ts）
   * @internal
   */
  private truncateSkillContent(skill: Skill, maxChars: number): string {
    if (skill.content.length <= maxChars) return skill.content;
    const result = truncateChapterContent(skill.content, {
      maxChars,
      silent: true, // 避免 dispatcher 流程的 spam 日志
      source: `skill:${skill.meta.id}`,
    });
    return result.text;
  }

  /**
   * 拼接 SKILL 为 prompt 文本
   * Sprint 14 T14-4: 集成 AttitudeFilter，sensei 档自动应用过滤
   * Sprint 14 T14-5: 支持 runtimeCtx（conditions 评估）
   * Sprint 14 T14-6: 支持 maxCharsPerSkill（content 级别截断）
   * @param phase 当前教学阶段
   * @param attitude 当前态度档位
   * @param options 过滤选项（见 SelectOptions）
   * @param runtimeCtx 运行时上下文（T14-5 新增）
   */
  composePrompt(
    phase: TeachingPhase,
    attitude: AttitudeLevel,
    options: SelectOptions = {},
    runtimeCtx: RuntimeContext = {},
  ): string {
    const skills = this.selectForPhase(phase, attitude, options, runtimeCtx);
    // Sprint 14 T14-6: content 级别截断（在 attitude filter 之前/之后均可；先截断后过滤更省）
    const processed = options.maxCharsPerSkill
      ? skills.map(s => ({
          ...s,
          content: this.truncateSkillContent(s, options.maxCharsPerSkill!),
        }))
      : skills;
    // Sprint 14 T14-4: 注入 attitude 过滤
    if (this.attitudeFilter) {
      return processed
        .map(s => this.attitudeFilter!.apply(s.content, attitude))
        .join('\n\n---\n\n');
    }
    return processed.map(s => s.content).join('\n\n---\n\n');
  }

  /** Sprint 14 T14-4: 注入 attitude 过滤 */
  setAttitudeFilter(filter: AttitudeFilter): void {
    this.attitudeFilter = filter;
  }

  /**
   * 估算总 token 数
   * @param phase 当前教学阶段
   * @param attitude 当前态度档位
   * @param options 过滤选项（见 SelectOptions）
   * @param runtimeCtx 运行时上下文（T14-5 新增）
   */
  estimateTokens(
    phase: TeachingPhase,
    attitude: AttitudeLevel,
    options: SelectOptions = {},
    runtimeCtx: RuntimeContext = {},
  ): number {
    const skills = this.selectForPhase(phase, attitude, options, runtimeCtx);
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
