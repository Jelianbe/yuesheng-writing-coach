/**
 * 学生模型服务 — 跨会话聚合，替代渲染进程死代码
 *
 * 职责：
 *   1. 从 SQLite 聚合所有会话的诊断数据，构建用户画像
 *   2. 提供实时计算能力（不缓存，数据量小，一致性优先）
 *   3. 导出为 Prompt 注入文本，替换 V3 Prompt 的 {student_context} 占位符
 *
 * 设计依据：
 *   - student-model-redesign_V1.0.md §2.2 StudentModel 数据结构
 *   - student-model-redesign_V1.0.md §3 StudentModelService 设计
 *   - SPEC_adaptive-teaching_V1.0.md §3 学生模型
 *   - teaching-knowledge-bridge_V1.0.md §4.1 StudentModelService
 *
 * 架构决策：
 *   - 数据来源从 localStorage 迁移到 SQLite 主进程聚合
 *   - 两个正交维度：proficiency（能力等级）+ cognitiveStyle（认知风格）
 *   - 跨会话聚合（不是单会话快照）
 */

import { ProfileDataAggregator } from './profile-data-aggregator';
import Database from 'better-sqlite3';
import { SYNDROME_NAMES } from '../../../shared/mappings';
import * as path from 'path';
import * as fs from 'fs';
import { severityToNumber } from '../../../shared/severity-utils';
import { calcTrendFromHistory, mapTrendLabel } from '../../../shared/trend-utils';

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
  SyndromeProfile,
  StudentProfileDescriptions,
  SeverityLevel,
} from './student-model-service.types';
import {
  computeCrossSessionConsistency,
  computeCognitiveStyleFromMessages,
} from './student-model-service.utils';

// ============ 服务类 ============

export class StudentModelService {
  private db: Database.Database;
  private aggregator: ProfileDataAggregator;
  private resourcesRoot: string;
  private descriptionsCache: StudentProfileDescriptions | null = null;

  constructor(
    db: Database.Database,
    aggregator: ProfileDataAggregator,
    resourcesRoot: string,
  ) {
    this.db = db;
    this.aggregator = aggregator;
    this.resourcesRoot = resourcesRoot;
  }

  /**
   * 获取症候画像（跨会话聚合）
   * @param sessionId - 可选，限定到某个会话；不传则聚合所有会话
   */
  getSyndromeProfile(sessionId?: string): SyndromeProfile {
    const diagnoses = sessionId
      ? this.aggregator.getDiagnosesBySession(sessionId)
      : this.aggregator.getAllDiagnoses();

    // 扁平化所有症候出现
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

      // 找到最后一个时间戳
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
   * 加载学生画像描述配置
   */
  loadDescriptionsConfig(): void {
    const configPath = path.join(this.resourcesRoot, 'config/student-profile-descriptions.json');

    try {
      const raw = fs.readFileSync(configPath, 'utf-8');
      this.descriptionsCache = JSON.parse(raw) as StudentProfileDescriptions;
    } catch (err) {
      console.error('[StudentModelService] Failed to load descriptions config:', err);
      this.descriptionsCache = null;
    }
  }

  /**
   * 获取学生画像描述文本
   */
  getDescriptions(): StudentProfileDescriptions {
    if (!this.descriptionsCache) {
      this.loadDescriptionsConfig();
    }
    // 返回默认值以防加载失败
    return this.descriptionsCache ?? {
      $source: 'default',
      proficiency: {
        beginner: '你处于学习初期，建议从基础练习开始。',
        intermediate: '你已掌握基础技巧，可以尝试更复杂的练习。',
        advanced: '你的写作能力已比较成熟，适合挑战高级技巧。',
      },
      cognitiveStyle: {
        analytical: '你喜欢逻辑分析，教学中多用框架和规则。',
        emotional: '你喜欢情感共鸣，教学中多引用故事。',
        mixed: '你适合灵活结合分析和体验两种方式。',
      },
      syndromeSummary: {
        noData: '暂无诊断数据。',
        hasIssues: '当前需要关注：{topIssue}。',
        improving: '你的写作正在进步中！继续努力。',
        multipleIssues: '你有多个需要注意的问题，建议从{topIssue}开始。',
      },
    };
  }

  /**
   * 推断用户能力等级
   * beginner: L3 >= 3 | L2 >= 5; intermediate: 有 L2; advanced: 最近 5 次全是 L1
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

    // L3 出现 ≥ MIN_L3_FOR_BEGINNER 次 → beginner（置信度随 L3 比例增加）
    if (l3Count >= MIN_L3_FOR_BEGINNER) {
      const confidence = Math.min(1, l3Count / total + 0.3);
      return { level: 'beginner', confidence };
    }

    // L2 出现 ≥ MIN_L2_FOR_BEGINNER 次 → beginner
    if (l2Count >= MIN_L2_FOR_BEGINNER) {
      const confidence = Math.min(1, l2Count / total + 0.2);
      return { level: 'beginner', confidence };
    }

    // 最近 RECENT_WINDOW 次全是 L1 → advanced
    const recent5 = allSeverities.slice(-RECENT_WINDOW);
    if (recent5.length >= MIN_RECENT_FOR_ADVANCED && recent5.every(s => s === 'L1')) {
      return { level: 'advanced', confidence: 0.8 };
    }

    // 默认 → intermediate
    const confidence = Math.min(0.8, total / DEFAULT_CONFIDENCE_DIVISOR);
    return { level: 'intermediate', confidence };
  }

  /**
   * 推断用户认知风格（CX-001-PROFILE：分层关键词 + 时效加权 + 跨会话一致性）
   */
  inferCognitiveStyle(): { style: CognitiveStyle; confidence: number } {
    const rows = this.db.prepare(
      "SELECT content, session_id, timestamp FROM messages WHERE role = 'user' ORDER BY timestamp ASC",
    ).all() as { content: string; session_id: string | null; timestamp: string }[];

    const flatMessages = rows.map(r => r.content);

    // 跨会话一致性：按 session 分组检测风格是否跨 session 一致
    const sessionIds = new Set(rows.map(r => r.session_id).filter(Boolean));
    let consistencyBonus = 0;
    if (sessionIds.size >= 2) {
      consistencyBonus = computeCrossSessionConsistency(rows);
    }

    return computeCognitiveStyleFromMessages(flatMessages, consistencyBonus);
  }

  /**
   * 获取训练成熟度（mature: 跳过引导; developing: 完整流程; minimal: 打基础）
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
   * 获取症候频次排行（按出现次数降序）
   *
   * @param topN - 返回前 N 个（不传则返回全部）
   * @param sessionId - 可选，限定到某个会话
   */
  getTopSyndromes(topN?: number, sessionId?: string): Array<{ id: string; name: string; count: number }> {
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
   *
   * 返回每个症候在最近 N 个会话中平均每次都出现的比率。
   * 频繁度 > 0.5 表示"反复出现的老问题"。
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
   *
   * 如果最近对话中症候严重度无改善且训练分数无上升 → 停滞
   */
  getStagnationStatus(): { stagnated: boolean; reason?: string } {
    const profile = this.getSyndromeProfile();
    const allSessions = new Set(Object.values(profile).flatMap(a => a.sessionIds));
    if (allSessions.size < MIN_SESSION_FOR_STAGNATION) {
      return { stagnated: false };
    }

    // 检查是否有 any 症候在恶化且无改善项
    const worsening = Object.entries(profile).filter(([, agg]) => agg.trend === 'worsening');
    const improving = Object.entries(profile).filter(([, agg]) => agg.trend === 'improving');
    if (worsening.length > 0 && improving.length === 0) {
      const names = worsening.map(([id]) => SYNDROME_NAMES[id] ?? id);
      return { stagnated: true, reason: `${names.join('、')}持续恶化` };
    }

    // 检查训练分数：最近三次 vs 之前三次
    const training = this.aggregator.getAllTrainings().filter(t => t.status === 'completed' && t.effectiveness != null);
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
   * 获取优选的症候聚焦列表（优先级：阅读体验 > 恶化趋势 > 出现频次）
   */
  getPrioritizedSyndromes(): Array<{ id: string; name: string; priority: number }> {
    const top = this.getTopSyndromes();
    const frequencyMap = this.getSyndromeFrequencyMap();

    const HIGH_PRIORITY = ['P006', 'P004'];
    const scored = top.map((s) => {
      let score = s.count * 10;
      // 影响阅读体验 → +50
      if (HIGH_PRIORITY.includes(s.id)) score += 50;
      // 频繁出现 → +30
      if ((frequencyMap[s.id] ?? 0) > 0.5) score += 30;
      return { ...s, priority: score };
    });

    return scored.sort((a, b) => b.priority - a.priority);
  }

  /**
   * 导出为 Prompt 注入文本（替换 V3 Prompt 的 {student_context} 占位符）
   */
  toPromptText(): string {
    const profile = this.getSyndromeProfile();
    const proficiency = this.inferProficiency();
    const cognitiveStyle = this.inferCognitiveStyle();
    const maturity = this.inferTrainingMaturity();
    const stagnation = this.getStagnationStatus();
    const lines: string[] = [];

    // 1. 基础画像（2 行）
    const proficiencyMap: Record<ProficiencyLevel, string> = {
      beginner: '新手写作者',
      intermediate: '进阶写作者',
      advanced: '成熟写作者',
    };
    const styleMap: Record<CognitiveStyle, string> = {
      analytical: '理性分析型',
      emotional: '实操导向型',
      mixed: '混合型',
    };
    const maturityMap: Record<string, string> = {
      mature: '教学适应度高',
      developing: '教学适应中',
      minimal: '教学适应低',
    };
    lines.push(`- 用户画像：${proficiencyMap[proficiency.level]}，${styleMap[cognitiveStyle.style]}，${maturityMap[maturity.maturity]}`);

    // 2. 停滞状态（1 行）
    if (stagnation.stagnated) {
      lines.push(`- 停滞预警：${stagnation.reason}，建议调整教学方式`);
    }

    // 3. 反复出现的问题
    const persistentProblems = Object.entries(profile)
      .filter(([, agg]) => agg.occurrenceCount >= MIN_OCCURRENCE_FOR_PERSISTENT)
      .map(([id]) => SYNDROME_NAMES[id] ?? id);

    if (persistentProblems.length > 0) {
      const sessionCount = new Set(
        Object.values(profile).flatMap(a => a.sessionIds),
      ).size;
      lines.push(`- 反复出现的问题：${persistentProblems.join('、')}（跨 ${sessionCount} 次对话）`);
    }

    // 4. 正在改善 / 恶化的信号
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

    // 5. 聚焦建议（1 行，仅当有明确目标时）
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

// ============ 重新导出（桶文件兼容） ============

export type {
  ProficiencyLevel,
  CognitiveStyle,
  TrainingMaturity,
  SyndromeAggregation,
  SyndromeProfile,
  StudentProfileDescriptions,
} from './student-model-service.types';

export {
  computeCrossSessionConsistency,
  computeCognitiveStyleFromMessages,
} from './student-model-service.utils';
