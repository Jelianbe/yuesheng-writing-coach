/**
 * 能力画像服务
 * 负责：实时聚合诊断数据，生成用户能力画像
 * 设计：不缓存，查询时实时计算（数据量小，一致性优先）
 * 依赖：diagnosis.service, training-record.service, ability-atlas.loader
 *
 * T15-C.3 改造：使用 ability-atlas.loader 替代手写 JSON 读取，
 * 消除重复实现，共享 loader 缓存。
 */

import type {
  AbilityProfile,
  AbilityScore,
  WeakPoint,
  SeverityLevel,
} from '../../../../shared/types/index';
import type { ProfileDataAggregator } from './profile-data-aggregator';
import { calcTrend as calcTrendDir, mapTrendLabel } from '../../../../shared/trend-utils';
import { SEVERITY_TO_SCORE, SEVERITY_TO_NUM } from '../../../../shared/severity-utils';

// T15-C.3: 改用 ability-atlas.loader 替代手写 JSON 读取
import {
  getAllAbilityNodes,
  getAllSyndromes,
} from '../ability-atlas/ability-atlas.loader';

// ============ 服务类 ============

export class AbilityProfileService {
  /**
   * @param aggregator 数据聚合器
   * @param _resourcesRoot 已废弃（T15-C.3 改造后通过 loader 读取）
   */
  constructor(
    private aggregator: ProfileDataAggregator,
    _resourcesRoot?: string,
  ) {}

  /**
   * 计算用户能力画像（实时聚合）
   */
  computeProfile(sessionId: string): AbilityProfile {
    // T15-C.3: 通过 loader 读取（带缓存）
    const abilities = getAllAbilityNodes();
    const syndromes = getAllSyndromes();
    const data = this.aggregator.getProfileData(sessionId);
    const occurrences = this.aggregateSyndromeOccurrences(data.diagnoses);

    return {
      sessionId,
      abilities: this.computeAbilityScores(abilities, occurrences),
      weakPoints: this.computeWeakPoints(syndromes, occurrences),
      trainingStats: this.computeTrainingStats(data.trainings),
      diagnosisTrend: this.computeDiagnosisTrend(data.diagnoses),
      computedAt: new Date().toISOString(),
    };
  }

  /** 聚合症候出现记录 */
  private aggregateSyndromeOccurrences(
    diagnoses: Array<{ syndromes: Array<{ id: string; severity: SeverityLevel; score?: number }>; timestamp: string; confidence: number }>,
  ): Record<string, { severity: SeverityLevel; timestamp: string; score: number; num: number }[]> {
    const occurrences: Record<string, { severity: SeverityLevel; timestamp: string; score: number; num: number }[]> = {};
    for (const d of diagnoses) {
      for (const s of d.syndromes) {
        if (!occurrences[s.id]) occurrences[s.id] = [];
        occurrences[s.id].push({
          severity: s.severity,
          timestamp: d.timestamp,
          score: SEVERITY_TO_SCORE[s.severity],
          num: SEVERITY_TO_NUM[s.severity],
        });
      }
    }
    return occurrences;
  }

  /** 计算能力评分 */
  private computeAbilityScores(
    abilities: Array<{ atlasId: string; name: string; syndromes: string[] }>,
    occurrences: Record<string, { severity: SeverityLevel; timestamp: string; score: number; num: number }[]>,
  ): AbilityScore[] {
    return abilities.map(ability => {
      const related = ability.syndromes;
      const allScores: number[] = [];
      const allNums: number[] = [];

      for (const sid of related) {
        const occs = occurrences[sid] ?? [];
        for (const o of occs) {
          allScores.push(o.score);
          allNums.push(o.num);
        }
      }

      const dataInsufficient = allScores.length < 3;
      const score = allScores.length > 0
        ? Math.round(allScores.reduce((a, b) => a + b, 0) / allScores.length)
        : 100;

      // 趋势：最近5次 vs 之前5次
      const recentNums = allNums.slice(-5);
      const previousNums = allNums.slice(-10, -5);
      const trend = calcTrendDir(recentNums, previousNums);

      return {
        abilityId: ability.atlasId, // T15-C.3: loader 用 atlasId，原 id 字段映射为 atlasId
        abilityName: ability.name,
        score: Math.min(100, Math.max(0, score)),
        relatedSyndromes: related,
        severityHistory: allNums,
        trend,
        dataInsufficient,
      };
    });
  }

  /** 计算弱点标签 */
  private computeWeakPoints(
    syndromes: Array<{ id: string; name: string }>,
    occurrences: Record<string, { severity: SeverityLevel; timestamp: string; score: number; num: number }[]>,
  ): WeakPoint[] {
    const weakPoints: WeakPoint[] = [];
    for (const syndrome of syndromes) {
      const occs = occurrences[syndrome.id] ?? [];
      if (occs.length === 0) continue;

      const nums = occs.map(o => o.num);
      const avgSeverity = nums.reduce((a, b) => a + b, 0) / nums.length;
      const maxSeverity = Math.max(...nums);

      // 判定：>=3次 或 (>=2次 且 最大严重度 >= L2)
      const isWeak = occs.length >= 3 || (occs.length >= 2 && maxSeverity >= 2);
      if (!isWeak) continue;

      const recent = nums.slice(-5);
      const previous = nums.slice(-10, -5);
      const trend = mapTrendLabel(calcTrendDir(recent, previous));

      weakPoints.push({
        syndromeId: syndrome.id,
        syndromeName: syndrome.name,
        occurrenceCount: occs.length,
        avgSeverity: Math.round(avgSeverity * 100) / 100,
        lastOccurrence: occs[occs.length - 1].timestamp,
        trend,
      });
    }
    return weakPoints;
  }

  /** 计算训练统计 */
  private computeTrainingStats(
    trainings: Array<{ syndromeId: string; status: string }>,
  ): AbilityProfile['trainingStats'] {
    const bySyndrome: Record<string, { assigned: number; completed: number }> = {};
    for (const t of trainings) {
      if (!bySyndrome[t.syndromeId]) bySyndrome[t.syndromeId] = { assigned: 0, completed: 0 };
      bySyndrome[t.syndromeId].assigned++;
      if (t.status === 'completed') bySyndrome[t.syndromeId].completed++;
    }
    const totalAssigned = trainings.length;
    const totalCompleted = trainings.filter(t => t.status === 'completed').length;

    return {
      totalAssigned,
      totalCompleted,
      completionRate: totalAssigned > 0 ? Math.round((totalCompleted / totalAssigned) * 100) / 100 : 0,
      bySyndrome,
    };
  }

  /** 计算诊断趋势 */
  private computeDiagnosisTrend(
    diagnoses: Array<{ syndromes: Array<{ id: string }>; confidence: number }>,
  ): AbilityProfile['diagnosisTrend'] {
    const syndromeFrequency: Record<string, number> = {};
    for (const d of diagnoses) {
      for (const s of d.syndromes) {
        syndromeFrequency[s.id] = (syndromeFrequency[s.id] ?? 0) + 1;
      }
    }

    return {
      totalDiagnoses: diagnoses.length,
      avgConfidence: diagnoses.length > 0
        ? Math.round((diagnoses.reduce((a, d) => a + d.confidence, 0) / diagnoses.length) * 100) / 100
        : 0,
      syndromeFrequency,
    };
  }
}
