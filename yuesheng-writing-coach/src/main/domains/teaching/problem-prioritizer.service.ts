/**
 * 问题优先级排序服务 — 决定"说什么"
 *
 * 职责：
 *   1. 读取 problem-tiering.json 配置
 *   2. 对诊断出的症候进行三级分类（致命伤/结构病/皮肤症）
 *   3. 按优先级排序，一次只返回最高优先级的那一个
 *
 * 设计依据：
 *   - teaching-knowledge-bridge_V1.0.md §4.3 ProblemPrioritizer
 *   - problem-tiering.json（症候分级映射）
 *   - SPEC_adaptive-teaching_V1.0.md §2.3 问题三级分类
 */

import * as fs from 'fs';
import * as path from 'path';


/** 问题层级 */
export type ProblemTier = 'fatal' | 'structural' | 'surface';

/** 处理动作 */
export type ProblemAction = 'must_fix' | 'priority' | 'deferrable';

/** 排序后的问题 */
export interface PrioritizedProblem {
  /** 症候 ID */
  syndromeId: string;
  /** 症候名称 */
  name: string;
  /** 问题层级 */
  tier: ProblemTier;
  /** 处理动作 */
  action: ProblemAction;
  /** 层级标签（中文） */
  tierLabel: string;
  /** 出现次数 */
  occurrenceCount: number;
  /** 严重度历史 */
  severityHistory: string[];
}

/** 问题分级配置（从 problem-tiering.json 加载） */
interface ProblemTieringConfig {
  $source: string;
  tiers: Array<{
    level: string;
    label: string;
    description: string;
    syndromes: string[];
    action: ProblemAction;
  }>;
  syndromeTierMapping: Record<string, { tier: ProblemTier; reason: string }>;
  maxPerTurn: number;
  prioritizationRule: string;
}

/**
 * 问题优先级排序服务
 */
export class ProblemPrioritizer {
  private resourcesRoot: string;
  private config: ProblemTieringConfig | null = null;

  constructor(resourcesRoot: string) {
    this.resourcesRoot = resourcesRoot;
  }

  /** 获取配置文件路径 */
  private getConfigPath(): string {
    return path.join(this.resourcesRoot, 'config/problem-tiering.json');
  }

  /** 加载问题分级配置 */
  private loadConfig(): ProblemTieringConfig {
    if (this.config) return this.config;

    const configPath = this.getConfigPath();
    try {
      const raw = fs.readFileSync(configPath, 'utf-8');
      this.config = JSON.parse(raw) as ProblemTieringConfig;
      return this.config;
    } catch {
      return this.getDefaultConfig();
    }
  }

  /** 默认配置（降级） */
  private getDefaultConfig(): ProblemTieringConfig {
    return {
      $source: 'hardcoded-fallback',
      tiers: [
        { level: 'fatal', label: '致命伤', description: '', syndromes: [], action: 'must_fix' },
        { level: 'structural', label: '结构病', description: '', syndromes: [], action: 'priority' },
        { level: 'surface', label: '皮肤症', description: '', syndromes: [], action: 'deferrable' },
      ],
      syndromeTierMapping: {},
      maxPerTurn: 1,
      prioritizationRule: '一次诊断，只反馈优先级最高的那一个',
    };
  }

  /**
   * 对症候列表进行优先级排序
   * @param syndromes - 诊断出的症候列表（带出现次数和严重度历史）
   * @returns 按优先级排序的问题列表
   */
  prioritize(syndromes: Array<{
    id: string;
    name: string;
    occurrenceCount: number;
    severityHistory: string[];
  }>): PrioritizedProblem[] {
    const config = this.loadConfig();
    const tierOrder: ProblemTier[] = ['fatal', 'structural', 'surface'];

    // 构建 tier 查找表（优先使用 syndromeTierMapping）
    const tierMap = config.syndromeTierMapping;

    const problems: PrioritizedProblem[] = [];

    for (const s of syndromes) {
      let tier: ProblemTier = 'surface';
      let action: ProblemAction = 'deferrable';
      let tierLabel = '皮肤症';

      // 从 syndromeTierMapping 查找
      if (tierMap[s.id]) {
        tier = tierMap[s.id].tier;
      } else {
        // 从 tiers 中查找
        for (const t of config.tiers) {
          if (t.syndromes.includes(s.id)) {
            tier = t.level as ProblemTier;
            action = t.action;
            tierLabel = t.label;
            break;
          }
        }
      }

      // 根据 tier 设置 action 和 label
      if (tier === 'fatal') {
        action = 'must_fix';
        tierLabel = '致命伤';
      } else if (tier === 'structural') {
        action = 'priority';
        tierLabel = '结构病';
      }

      problems.push({
        syndromeId: s.id,
        name: s.name,
        tier,
        action,
        tierLabel,
        occurrenceCount: s.occurrenceCount,
        severityHistory: s.severityHistory,
      });
    }

    // 按 tier 优先级排序
    problems.sort((a, b) => tierOrder.indexOf(a.tier) - tierOrder.indexOf(b.tier));

    return problems;
  }

  /**
   * 获取最高优先级的问题（一次只说一个）
   */
  getTopProblem(syndromes: Array<{
    id: string;
    name: string;
    occurrenceCount: number;
    severityHistory: string[];
  }>): PrioritizedProblem | null {
    const prioritized = this.prioritize(syndromes);
    return prioritized.length > 0 ? prioritized[0] : null;
  }

  /** 清除配置缓存 */
  clearCache(): void {
    this.config = null;
  }
}
