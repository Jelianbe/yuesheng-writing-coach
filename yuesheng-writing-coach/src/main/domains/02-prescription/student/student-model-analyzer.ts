/**
 * 学生模型分析器 — 跨会话聚合 + 能力/风格/停滞推理
 *
 * 从 student-model-service.ts 拆分，职责：
 *   1. 从 ProfileDataAggregator 聚合诊断数据
 *   2. 提供 proficiency / cognitiveStyle / trainingMaturity 推理
 *   3. 导出为 Prompt 注入文本
 */

import type Database from 'better-sqlite3';
import { SYNDROME_NAMES } from '../../../../shared/mappings';
import { severityToNumber } from '../../../../shared/severity-utils';
import { calcTrendFromHistory, mapTrendLabel } from '../../../../shared/trend-utils';
import type { ProfileDataAggregator } from './profile-data-aggregator';
import {
  MIN_L3_FOR_BEGINNER,
  MIN_L2_FOR_BEGINNER,
  RECENT_WINDOW,
  MIN_RECENT_FOR_ADVANCED,
  DEFAULT_CONFIDENCE_DIVISOR,
  MIN_OCCURRENCE_FOR_PERSISTENT,
  MIN_SESSION_FOR_STAGNATION,
  TRAINING_COMPLETION_FOR_MATURE,
} from './student-model-service.types';
import type {
  ProficiencyLevel,
  CognitiveStyle,
  TrainingMaturity,
  SyndromeAggregation,
  SeverityLevel,
  StudentProfileDescriptions,
} from './student-model-service.types';
import {
  computeCrossSessionConsistency,
  computeCognitiveStyleFromMessages,
} from './student-model-service.utils';

/**
 * 学生模型分析器
 * 职责：聚合诊断数据、推理能力等级/认知风格/训练成熟度/停滞状态
 */
export class StudentModelAnalyzer {
  private aggregator: ProfileDataAggregator;
  private db: Database.Database;

  constructor(
    aggregator: ProfileDataAggregator,
    db: Database.Database,
  ) {
    this.aggregator = aggregator;
    this.db = db;
  }

  /**
   * 获取症候画像（跨会话聚合）
   */
  getSyndromeProfile(sessionId?: string): Record<string, SyndromeAggregation> {
    const diagnoses = sessionId
      ? this.aggregator.getDiagnosesBySession(sessionId)
      : this.aggregator.getAllDiagnoses();

    const syndromeEntries: Array<{
      id: string;
      severity: SeverityLevel;
      timestamp: string;
      sessionId: string;
    }> = [];

    for (const d of diagnoses) {
      for (const s of d.syndromes) {
        syndromeEntries.push({
          id: s.id,
          severity: s.severity,
          timestamp: d.timestamp,
          sessionId: d.sessionId,
        });
      }
    }

    return this.aggregateBySyndrome(syndromeEntries);
  }

  /**
   * 聚合症候数据
   */
  private aggregateBySyndrome(
    entries: Array<{ id: string; severity: SeverityLevel; timestamp: string; sessionId: string }>,
  ): Record<string, SyndromeAggregation> {
    const grouped: Record<string, {
      severities: SeverityLevel[];
      timestamps: string[];
      sessionIds: Set<string>;
    }> = {};

    for (const entry of entries) {
      if (!grouped[entry.id]) {
        grouped[entry.id] = {
          severities: [],
          timestamps: [],
          sessionIds: new Set(),
        };
      }
      grouped[entry.id].severities.push(entry.severity);
      grouped[entry.id].timestamps.push(entry.timestamp);
      grouped[entry.id].sessionIds.add(entry.sessionId);
    }

    const result: Record<string, SyndromeAggregation> = {};

    for (const [id, data] of Object.entries(grouped)) {
      const numHistory = data.severities.map(s => severityToNumber(s));
      const trend = mapTrendLabel(calcTrendFromHistory(numHistory));

      const lastSeenAt = data.timestamps.length > 0
        ? data.timestamps[data.timestamps.length - 1]
        : '';

      result[id] = {
        occurrenceCount: data.severities.length,
        latestSeverity: data.severities[data.severities.length - 1],
        severityHistory: data.severities,
        trend,
        lastSeenAt,
        sessionIds: Array.from(data.sessionIds),
      };
    }

    return result;
  }

  /**
   * 推断用户能力等级
   */
  inferProficiency(): { level: ProficiencyLevel; confidence: number } {
    const profile = this.getSyndromeProfile();
    const allSeverities: string[] = [];

    for (const agg of Object.values(profile)) {
      allSeverities.push(...agg.severityHistory);
    }

    const l3Count = allSeverities.filter(s => s === 'L3').length;
    const l2Count = allSeverities.filter(s => s === 'L2').length;
    const total = allSeverities.length;

    if (total === 0) {
      return { level: 'beginner', confidence: 0 };
    }

    if (l3Count >= MIN_L3_FOR_BEGINNER) {
      const confidence = Math.min(1, l3Count / total + 0.3);
      return { level: 'beginner', confidence };
    }

    if (l2Count >= MIN_L2_FOR_BEGINNER) {
      const confidence = Math.min(1, l2Count / total + 0.2);
      return { level: 'beginner', confidence };
    }

    const recent5 = allSeverities.slice(-RECENT_WINDOW);
    if (recent5.length >= MIN_RECENT_FOR_ADVANCED && recent5.every(s => s === 'L1')) {
      return { level: 'advanced', confidence: 0.8 };
    }

    const confidence = Math.min(0.8, total / DEFAULT_CONFIDENCE_DIVISOR);
    return { level: 'intermediate', confidence };
  }

  /**
   * 推断用户认知风格
   */
  inferCognitiveStyle(): { style: CognitiveStyle; confidence: number } {
    const rows = this.db.prepare(
      "SELECT content, session_id, timestamp FROM messages WHERE role = 'user' ORDER BY timestamp ASC",
    ).all() as { content: string; session_id: string | null; timestamp: string }[];

    const flatMessages = rows.map(r => r.content);

    const sessionIds = new Set(rows.map(r => r.session_id).filter(Boolean));
    let consistencyBonus = 0;
    if (sessionIds.size >= 2) {
      consistencyBonus = computeCrossSessionConsistency(rows);
    }

    return computeCognitiveStyleFromMessages(flatMessages, consistencyBonus);
  }

  /**
   * 获取训练成熟度
   */
  inferTrainingMaturity(): { maturity: TrainingMaturity; confidence: number } {
    const training = this.aggregator.getAllTrainings();
    if (training.length === 0) {
      return { maturity: 'minimal', confidence: 0.5 };
    }
    const completedCount = training.filter(t => t.status === 'completed').length;
    const completionRate = completedCount / training.length;
    const scoredTraining = training.filter(t => t.effectiveness != null);
    const avgScore = scoredTraining.length > 0
      ? scoredTraining.reduce((sum, t) => sum + (t.effectiveness ?? 0), 0) / scoredTraining.length
      : 0;

    if (completionRate >= TRAINING_COMPLETION_FOR_MATURE && avgScore >= 6) {
      return { maturity: 'mature', confidence: 0.7 };
    }
    if (completionRate >= 0.3) {
      return { maturity: 'developing', confidence: 0.6 };
    }
    return { maturity: 'minimal', confidence: 0.5 };
  }

  /**
   * 获取症候频次排行
   */
  getTopSyndromes(
    topN?: number,
    sessionId?: string,
  ): Array<{ id: string; name: string; count: number }> {
    const profile = this.getSyndromeProfile(sessionId);
    const entries = Object.entries(profile)
      .map(([id, agg]) => ({
        id,
        name: SYNDROME_NAMES[id] ?? id,
        count: agg.occurrenceCount,
      }))
      .sort((a, b) => b.count - a.count);

    return topN ? entries.slice(0, topN) : entries;
  }

  /**
   * 获取症候频繁度（按会话频率计算）
   */
  getSyndromeFrequencyMap(): Record<string, number> {
    const profile = this.getSyndromeProfile();
    const sessionIds = new Set<string>();
    for (const agg of Object.values(profile)) {
      for (const sid of agg.sessionIds) {
        sessionIds.add(sid);
      }
    }
    const totalSessions = sessionIds.size;
    if (totalSessions === 0) return {};

    const result: Record<string, number> = {};
    for (const [id, agg] of Object.entries(profile)) {
      result[id] = agg.sessionIds.length / totalSessions;
    }
    return result;
  }

  /**
   * 检测学习停滞状态
   */
  getStagnationStatus(): { stagnated: boolean; reason?: string } {
    const profile = this.getSyndromeProfile();
    const allSessions = new Set(Object.values(profile).flatMap(a => a.sessionIds));
    if (allSessions.size < MIN_SESSION_FOR_STAGNATION) {
      return { stagnated: false };
    }

    const worsening = Object.entries(profile).filter(([, agg]) => agg.trend === 'worsening');
    const improving = Object.entries(profile).filter(([, agg]) => agg.trend === 'improving');
    if (worsening.length > 0 && improving.length === 0) {
      const names = worsening.map(([id]) => SYNDROME_NAMES[id] ?? id);
      return { stagnated: true, reason: `${names.join('、')}持续恶化` };
    }

    const training = this.aggregator.getAllTrainings()
      .filter(t => t.status === 'completed' && t.effectiveness != null);
    if (training.length >= MIN_SESSION_FOR_STAGNATION) {
      const recent = training.slice(-3);
      const older = training.slice(0, -3);
      if (older.length > 0) {
        const recentAvg = recent.reduce((s, t) => s + (t.effectiveness ?? 0), 0) / recent.length;
        const olderAvg = older.reduce((s, t) => s + (t.effectiveness ?? 0), 0) / older.length;
        if (recentAvg <= olderAvg) {
          return { stagnated: true, reason: '训练分数无提升' };
        }
      }
    }

    return { stagnated: false };
  }

  /**
   * 获取优选的症候聚焦列表
   */
  getPrioritizedSyndromes(): Array<{ id: string; name: string; priority: number }> {
    const top = this.getTopSyndromes();
    const frequencyMap = this.getSyndromeFrequencyMap();

    const HIGH_PRIORITY = ['P006', 'P004'];
    const scored = top.map((s) => {
      let score = s.count * 10;
      if (HIGH_PRIORITY.includes(s.id)) score += 50;
      if ((frequencyMap[s.id] ?? 0) > 0.5) score += 30;
      return { ...s, priority: score };
    });

    return scored.sort((a, b) => b.priority - a.priority);
  }

  /**
   * 导出为 Prompt 注入文本
   * @param descriptions - 可选的学生画像描述配置（标签从外置 JSON 加载）
   */
  toPromptText(descriptions?: StudentProfileDescriptions): string {
    const profile = this.getSyndromeProfile();
    const proficiency = this.inferProficiency();
    const cognitiveStyle = this.inferCognitiveStyle();
    const maturity = this.inferTrainingMaturity();
    const stagnation = this.getStagnationStatus();
    const lines: string[] = [];

    // 标签从外置配置加载，fallback 到原始 key
    const proficiencyMap = descriptions?.proficiencyLabel as Record<string, string> | undefined;
    const styleMap = descriptions?.cognitiveStyleLabel as Record<string, string> | undefined;
    const maturityMap = descriptions?.trainingMaturityLabel as Record<string, string> | undefined;
    const profLabel = proficiencyMap?.[proficiency.level] ?? proficiency.level;
    const styleLabel = styleMap?.[cognitiveStyle.style] ?? cognitiveStyle.style;
    const matLabel = maturityMap?.[maturity.maturity] ?? maturity.maturity;
    lines.push(`- 用户画像：${profLabel}，${styleLabel}，${matLabel}`);

    if (stagnation.stagnated) {
      lines.push(`- 停滞预警：${stagnation.reason}，建议调整教学方式`);
    }

    const persistentProblems = Object.entries(profile)
      .filter(([, agg]) => agg.occurrenceCount >= MIN_OCCURRENCE_FOR_PERSISTENT)
      .map(([id]) => SYNDROME_NAMES[id] ?? id);

    if (persistentProblems.length > 0) {
      const sessionCount = new Set(
        Object.values(profile).flatMap(a => a.sessionIds),
      ).size;
      lines.push(`- 反复出现的问题：${persistentProblems.join('、')}（跨 ${sessionCount} 次对话）`);
    }

    const improvingProblems = Object.entries(profile)
      .filter(([, agg]) => agg.trend === 'improving')
      .map(([id]) => SYNDROME_NAMES[id] ?? id);
    const worseningProblems = Object.entries(profile)
      .filter(([, agg]) => agg.trend === 'worsening')
      .map(([id]) => SYNDROME_NAMES[id] ?? id);

    if (improvingProblems.length > 0) {
      lines.push(`- 正在改善：${improvingProblems.join('、')}`);
    }
    if (worseningProblems.length > 0) {
      lines.push(`- 需要关注：${worseningProblems.join('、')}（最近有恶化趋势）`);
    }

    const top = this.getPrioritizedSyndromes();
    if (top.length > 0) {
      const focusNames = top.slice(0, 2).map(s => s.name).join('、');
      lines.push(`- 建议聚焦：${focusNames}`);
    }

    return lines.join('\n');
  }

  /**
   * 获取症候名称
   */
  getSyndromeName(id: string): string {
    return SYNDROME_NAMES[id] ?? id;
  }
}
