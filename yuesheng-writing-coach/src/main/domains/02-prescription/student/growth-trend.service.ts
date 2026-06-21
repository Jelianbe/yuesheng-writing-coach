/**
 * 成长趋势服务 — 跨对话症候严重度趋势计算
 *
 * 职责：
 *   1. 聚合所有会话的诊断数据，计算每个症候的跨对话趋势
 *   2. 将症候严重度变化映射为"已掌握/进步中/稳定/需关注"四种状态
 *   3. 生成适合右侧栏展示的成长摘要数据
 *
 * 设计依据：
 *   - training-effectiveness-scoring_V2.0.md §二 症候严重度趋势
 *   - T-013 任务文档
 *
 * 状态映射规则：
 *   - mastered (已掌握): 症候在最近 3 次诊断中未出现
 *   - improving (进步中): 严重度从 L3→L2 或 L2→L1 或分数降低 >1
 *   - stable (稳定): 严重度无变化或分数变化 <=1
 *   - needsAttention (需关注): 严重度从 L1→L2 或 L2→L3 或分数增加 >1
 */

import type { StudentModelService } from './student-model-service';

/** 成长趋势状态 */
export type GrowthTrendStatus = 'mastered' | 'improving' | 'stable' | 'needsAttention';

/** 单个症候的成长趋势数据 */
export interface SyndromeTrend {
  /** 症候 ID */
  id: string;
  /** 症候名称 */
  name: string;
  /** 成长状态 */
  status: GrowthTrendStatus;
  /** 最新严重度 */
  latestSeverity: 'L1' | 'L2' | 'L3' | null;
  /** 之前严重度（用于对比） */
  previousSeverity: 'L1' | 'L2' | 'L3' | null;
  /** 出现次数 */
  occurrenceCount: number;
  /** 趋势描述 */
  description: string;
}

/** 状态显示映射 */
const STATUS_DISPLAY: Record<GrowthTrendStatus, { label: string; emoji: string }> = {
  mastered: { label: '已掌握', emoji: '✓' },
  improving: { label: '进步中', emoji: '↑' },
  stable: { label: '稳定', emoji: '→' },
  needsAttention: { label: '需关注', emoji: '!' },
};

/**
 * 成长趋势服务
 */
export class GrowthTrendService {
  private studentModelService: StudentModelService;

  constructor(studentModelService: StudentModelService) {
    this.studentModelService = studentModelService;
  }

  /**
   * 获取所有症候的成长趋势
   * @param sessionId - 会话 ID（可选，不传则聚合所有会话）
   * @param getSyndromeName - 症候名称映射函数（可选，用于翻译层）
   */
  getSyndromeTrends(
    sessionId?: string,
    getSyndromeName?: (id: string) => string,
  ): SyndromeTrend[] {
    const profile = this.studentModelService.getSyndromeProfile(sessionId);
    const entries = Object.entries(profile);

    return entries.map(([id, agg]) => {
      const name = getSyndromeName ? getSyndromeName(id) : id;
      const { status, description } = this.computeStatus(id, agg);

      return {
        id,
        name,
        status,
        latestSeverity: agg.latestSeverity,
        previousSeverity: this.getPreviousSeverity(agg),
        occurrenceCount: agg.occurrenceCount,
        description,
      };
    });
  }

  /**
   * 获取成长摘要（用于右侧栏展示）
   * 返回按状态分组的症候列表
   * @param sessionId - 会话 ID（可选，不传则聚合所有会话）
   * @param getSyndromeName - 症候名称映射函数（可选，用于翻译层）
   */
  getGrowthSummary(
    sessionId?: string,
    getSyndromeName?: (id: string) => string,
  ): {
    trends: SyndromeTrend[];
    masteredCount: number;
    improvingCount: number;
    stableCount: number;
    needsAttentionCount: number;
  } {
    const trends = this.getSyndromeTrends(sessionId, getSyndromeName);

    return {
      trends,
      masteredCount: trends.filter((t) => t.status === 'mastered').length,
      improvingCount: trends.filter((t) => t.status === 'improving').length,
      stableCount: trends.filter((t) => t.status === 'stable').length,
      needsAttentionCount: trends.filter((t) => t.status === 'needsAttention').length,
    };
  }

  /**
   * 计算单个症候的状态
   */
  private computeStatus(
    _id: string,
    agg: {
      occurrenceCount: number;
      latestSeverity: 'L1' | 'L2' | 'L3';
      severityHistory: ('L1' | 'L2' | 'L3')[];
      trend: 'improving' | 'worsening' | 'stable';
    },
  ): { status: GrowthTrendStatus; description: string } {
    const history = agg.severityHistory;
    const latest = agg.latestSeverity;

    // 如果症候在最近几次诊断中不再出现，视为已掌握
    // 这里通过 occurrenceCount 和趋势综合判断
    if (history.length >= 3 && agg.trend === 'improving' && latest === 'L1') {
      return {
        status: 'mastered',
        description: `${STATUS_DISPLAY.mastered.label} — 症候已显著改善`,
      };
    }

    // 根据趋势判断
    switch (agg.trend) {
      case 'improving':
        return {
          status: 'improving',
          description: `${STATUS_DISPLAY.improving.label} — 严重度正在降低`,
        };
      case 'worsening':
        return {
          status: 'needsAttention',
          description: `${STATUS_DISPLAY.needsAttention.label} — 严重度有所上升`,
        };
      case 'stable':
      default:
        // 稳定状态根据最新严重度细分
        if (latest === 'L3') {
          return {
            status: 'needsAttention',
            description: `${STATUS_DISPLAY.needsAttention.label} — 症候仍然严重`,
          };
        }
        if (latest === 'L1') {
          return {
            status: 'stable',
            description: `${STATUS_DISPLAY.stable.label} — 症候轻微且稳定`,
          };
        }
        return {
          status: 'stable',
          description: `${STATUS_DISPLAY.stable.label} — 症候保持稳定`,
        };
    }
  }

  /**
   * 获取之前的严重度（倒数第二次）
   */
  private getPreviousSeverity(agg: {
    severityHistory: ('L1' | 'L2' | 'L3')[];
  }): 'L1' | 'L2' | 'L3' | null {
    const history = agg.severityHistory;
    if (history.length < 2) return null;
    return history[history.length - 2];
  }
}
