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

import { DiagnosisService } from './diagnosis.service';
import { TrainingRecordService } from './training-record.service';
import Database from 'better-sqlite3';
import { SYNDROME_NAMES } from '../../shared/mappings';
import * as path from 'path';
import * as fs from 'fs';
import { severityToNumber } from '../../shared/severity-utils';
import { calcTrendFromHistory, mapTrendLabel } from '../../shared/trend-utils';
import type { SeverityLevel } from '../../renderer/shared/types';

// ============ 能力等级判定阈值 ============

/** L3 出现 ≥ 此值 → beginner */
const MIN_L3_FOR_BEGINNER = 3;
/** L2 出现 ≥ 此值 → beginner */
const MIN_L2_FOR_BEGINNER = 5;
/** 最近 N 次诊断窗口 */
const RECENT_WINDOW = 5;
/** 最近 N 次全是 L1 → advanced */
const MIN_RECENT_FOR_ADVANCED = 5;
/** 置信度默认除数 */
const DEFAULT_CONFIDENCE_DIVISOR = 10;

/** 认知风格判定所需最少消息数（入场诊断） */
const MIN_MESSAGES_FOR_STYLE = 2;
/** 入场诊断置信度缩放（消息不足时） */
const MIN_STYLE_CONFIDENCE_SCALE = 0.5;
/** 分析型比例 ≥ 此值 → analytical */
const ANALYTICAL_THRESHOLD = 0.6;
/** 情感型比例 ≤ 此值 → emotional */
const EMOTIONAL_THRESHOLD = 0.4;
/** 最近消息权重系数 */
const RECENCY_WEIGHT = 1.5;
/** 旧消息权重系数 */
const HISTORY_WEIGHT = 0.5;
/** 最近消息窗口 */
const RECENCY_WINDOW = 3;
/** 强信号关键词权重 */
const TIER_1_WEIGHT = 2;
/** 弱信号关键词权重 */
const TIER_3_WEIGHT = 0.5;

/** 分层关键词体系 — 分析型 */
const ANALYTICAL_KEYWORDS: Array<{ words: string[]; tier: 1 | 2 | 3 }> = [
  { tier: 1, words: ['结构', '因果关系', '逻辑关系', '对比', '层次', '一致性'] },
  { tier: 2, words: ['为什么', '怎么理解', '本质', '核心', '逻辑', '意义', '深层', '框架', '方向', '理念', '分析', '系统', '论证', '批判'] },
  { tier: 3, words: ['定义', '规律', '模式', '分类', '推理', '原由', '机制'] },
];

/** 分层关键词体系 — 情感型 */
const EMOTIONAL_KEYWORDS: Array<{ words: string[]; tier: 1 | 2 | 3 }> = [
  { tier: 1, words: ['感觉', '共鸣', '打动', '代入', '沉浸', '氛围'] },
  { tier: 2, words: ['怎么做', '给范例', '改一下', '示范', '体验', '情感', '冲突', '生动', '感染力', '细腻'] },
  { tier: 3, words: ['故事', '共鸣点', '场景', '对话', '人物', '情绪', '温度'] },
];

/** 反复出现问题的发生次数阈值 */
const MIN_OCCURRENCE_FOR_PERSISTENT = 3;
/** 停滞判定所需最小会话数 */
const MIN_SESSION_FOR_STAGNATION = 3;
/** 训练完成率 ≥ 此值 → 成熟 */
const TRAINING_COMPLETION_FOR_MATURE = 0.6;
/** 能力等级 */
export type ProficiencyLevel = 'beginner' | 'intermediate' | 'advanced';

/** 认知风格 */
export type CognitiveStyle = 'analytical' | 'emotional' | 'mixed';

/** 症候聚合数据 */
interface SyndromeAggregation {
  occurrenceCount: number;
  latestSeverity: SeverityLevel;
  severityHistory: SeverityLevel[];
  trend: 'improving' | 'worsening' | 'stable';
  lastSeenAt: string;
  sessionIds: string[];
}

/** 症候画像 — 症候 ID → 聚合数据 */
export type SyndromeProfile = Record<string, SyndromeAggregation>;

/** 学生画像描述配置 */
export interface StudentProfileDescriptions {
  $source: string;
  proficiency: Record<string, string>;
  cognitiveStyle: Record<string, string>;
  syndromeSummary: {
    noData: string;
    hasIssues: string;
    improving: string;
    multipleIssues: string;
  };
}

// ============ 服务类 ============

export class StudentModelService {
  private db: Database.Database;
  private diagnosisService: DiagnosisService;
  private trainingService!: TrainingRecordService;
  private resourcesRoot: string;
  private descriptionsCache: StudentProfileDescriptions | null = null;

  constructor(
    db: Database.Database,
    diagnosisService: DiagnosisService,
    trainingService: TrainingRecordService,
    resourcesRoot: string,
  ) {
    this.db = db;
    this.diagnosisService = diagnosisService;
    this.trainingService = trainingService;
    this.resourcesRoot = resourcesRoot;
  }

  /**
   * 获取症候画像（跨会话聚合）
   *
   * 查询所有诊断记录，按症候 ID 聚合，计算每个症候的出现次数、
   * 最新严重度、严重度历史、趋势和涉及的会话。
   *
   * @param sessionId - 可选，限定到某个会话；不传则聚合所有会话
   */
  getSyndromeProfile(sessionId?: string): SyndromeProfile {
    const diagnoses = sessionId
      ? this.diagnosisService.getBySession(sessionId)
      : this.diagnosisService.getAll();

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
   *
   * 规则：
   *   beginner:   L3 出现 >= 3 次，或 L2 出现 >= 5 次
   *   intermediate: 有 L2 但 < 5 次，或最近趋势 = improving
   *   advanced:   最近 5 次诊断全是 L1
   */
  inferProficiency(): { level: ProficiencyLevel; confidence: number } {
    const profile = this.getSyndromeProfile();
    const allSeverities: SeverityLevel[] = [];

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
   * 推断用户认知风格
   *
   * CX-001-PROFILE 改进（V3.5）：
   *   1. 分层关键词体系（3 层权重 + 反信号排除）
   *   2. 消息时效性加权（最近 3 条权重 ×1.5，旧消息 ×0.5）
   *   3. 入场短文诊断（≥2 条消息即可判定，置信度按数据量缩放）
   *   4. 跨会话一致性加分
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
   * 获取训练成熟度

  /**
   * 获取训练成熟度
   *
   * 基于训练记录推断用户对教学流程的适应程度。
   * mature → 可以跳过引导直接给出建议
   * developing → 需要完整教学流程
   * minimal → 优先打基础
   */
  inferTrainingMaturity(): { maturity: 'mature' | 'developing' | 'minimal'; confidence: number } {
    const training = this.trainingService.getAll();
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
    const training = this.trainingService.getAll().filter(t => t.status === 'completed' && t.effectiveness != null);
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
   * 获取优选的症候聚焦列表（按优先级排序）
   *
   * 优先级规则（与 R-011~R-015 一致）：
   *   1. 影响阅读体验的症候优先（P006, P004）
   *   2. 恶化趋势优先
   *   3. 出现频次优先
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
   * 导出为 Prompt 注入文本
   * 替换 V3 Prompt 中的 {student_context} 占位符
   *
   * 格式设计原则：
   *   1. 简洁 — 不超过 300 字
   *   2. 可操作 — AI 能据此调整教学策略
   *   3. 动态 — 每次查询都反映最新状态
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

// ============ 独立计算函数（可测试的纯函数） ============

/**
 * 跨会话一致性检测
 *
 * 按 session 分组计算每个会话的主导风格，
 * 如果所有 session 风格一致则返回加分。
 */
function computeCrossSessionConsistency(
  rows: { content: string; session_id: string | null }[],
): number {
  const sessionStyles: Array<'analytical' | 'emotional'>[] = [];
  let currentSession: { analytical: number; emotional: number } | null = null;
  let currentSessionId: string | null = null;

  for (const row of rows) {
    if (!row.session_id) continue;
    if (row.session_id !== currentSessionId) {
      if (currentSession) {
        sessionStyles.push(
          currentSession.analytical > currentSession.emotional
            ? ['analytical']
            : ['emotional'],
        );
      }
      currentSession = { analytical: 0, emotional: 0 };
      currentSessionId = row.session_id;
    }
    if (currentSession) {
      for (const group of ANALYTICAL_KEYWORDS) {
        for (const kw of group.words) {
          if (row.content.includes(kw)) currentSession.analytical++;
        }
      }
      for (const group of EMOTIONAL_KEYWORDS) {
        for (const kw of group.words) {
          if (row.content.includes(kw)) currentSession.emotional++;
        }
      }
    }
  }
  // 最后一个 session
  if (currentSession) {
    sessionStyles.push(
      currentSession.analytical > currentSession.emotional
        ? ['analytical']
        : ['emotional'],
    );
  }

  // 检查所有 session 风格一致
  const uniqueStyles = new Set(sessionStyles.flat());
  if (uniqueStyles.size === 1 && uniqueStyles.has('analytical')) {
    return 0.1;
  }
  if (uniqueStyles.size === 1 && uniqueStyles.has('emotional')) {
    return 0.1;
  }
  return 0;
}

/**
 * 从消息列表计算认知风格（纯函数，无 DB 依赖）
 *
 * @param messages - 用户消息文本数组（按时间正序）
 * @param consistencyBonus - 跨会话一致性加分（由调用方传入）
 */
export function computeCognitiveStyleFromMessages(
  messages: string[],
  consistencyBonus: number = 0,
): { style: CognitiveStyle; confidence: number } {
  const msgCount = messages.length;

  // 0 条 → 数据不足
  if (msgCount === 0) {
    return { style: 'mixed', confidence: 0 };
  }

  // === 关键词统计（分层加权 + 时效加权） ===

  let analyticalScore = 0;
  let emotionalScore = 0;
  let totalMatchCount = 0;

  for (let i = 0; i < msgCount; i++) {
    const content = messages[i];
    // 时效权重：最近 RECENCY_WINDOW 条 ×1.5，其余 ×0.5
    const timeWeight = i >= msgCount - RECENCY_WINDOW ? RECENCY_WEIGHT : HISTORY_WEIGHT;

    for (const group of ANALYTICAL_KEYWORDS) {
      const tierWeight = group.tier === 1 ? TIER_1_WEIGHT : group.tier === 3 ? TIER_3_WEIGHT : 1;
      for (const kw of group.words) {
        if (content.includes(kw)) {
          analyticalScore += tierWeight * timeWeight;
          totalMatchCount++;
        }
      }
    }

    for (const group of EMOTIONAL_KEYWORDS) {
      const tierWeight = group.tier === 1 ? TIER_1_WEIGHT : group.tier === 3 ? TIER_3_WEIGHT : 1;
      for (const kw of group.words) {
        if (content.includes(kw)) {
          emotionalScore += tierWeight * timeWeight;
          totalMatchCount++;
        }
      }
    }
  }

  // 无匹配关键词 → mixed
  if (totalMatchCount === 0) {
    return { style: 'mixed', confidence: 0 };
  }

  // === 风格判定 ===

  const totalScore = analyticalScore + emotionalScore;
  const analyticalRatio = analyticalScore / totalScore;

  let style: CognitiveStyle;
  let baseConfidence: number;

  if (analyticalRatio >= ANALYTICAL_THRESHOLD) {
    style = 'analytical';
    baseConfidence = analyticalRatio;
  } else if (analyticalRatio <= EMOTIONAL_THRESHOLD) {
    style = 'emotional';
    baseConfidence = 1 - analyticalRatio;
  } else {
    style = 'mixed';
    baseConfidence = 0.5;
  }

  // === 置信度精算 ===

  // 消息数调整：消息越多越可信，上限 1.0
  const dataMultiplier = Math.min(1, msgCount / 10);
  // 入场诊断缩放：消息不足时降低置信度
  const entryScale = msgCount < MIN_MESSAGES_FOR_STYLE
    ? MIN_STYLE_CONFIDENCE_SCALE
    : Math.min(1, msgCount / 5);

  const rawConfidence = baseConfidence * dataMultiplier + consistencyBonus;
  const finalConfidence = Math.min(1, rawConfidence * entryScale);

  return { style, confidence: Math.round(finalConfidence * 100) / 100 };
}
