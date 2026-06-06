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
import { TrainingRecordService, TrainingRecord } from './training-record.service';
import Database from 'better-sqlite3';
import { SYNDROME_NAMES, ABILITY_NAMES, SYNDROME_TO_ABILITIES, ACTION_NAMES } from '../../shared/mappings';
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

/** 认知风格判定所需最少消息数 */
const MIN_MESSAGES_FOR_STYLE = 5;
/** 分析型比例 ≥ 此值 → analytical */
const ANALYTICAL_THRESHOLD = 0.6;
/** 情感型比例 ≤ 此值 → emotional */
const EMOTIONAL_THRESHOLD = 0.4;

/** 反复出现问题的发生次数阈值 */
const MIN_OCCURRENCE_FOR_PERSISTENT = 3;

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

/**
 * 计算趋势：后一半 vs 前一半
 * 数值下降 = improving（严重度降低），上升 = worsening
 * 委托至共享 trend-utils
 */
function calcTrend(history: number[]): 'improving' | 'worsening' | 'stable' {
  return mapTrendLabel(calcTrendFromHistory(history));
}

// ============ 服务类 ============

export class StudentModelService {
  private db: Database.Database;
  private diagnosisService: DiagnosisService;
  private trainingService: TrainingRecordService;
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
      const trend = calcTrend(numHistory);

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
   * 规则（基于用户消息中的提问模式）：
   *   analytical: "为什么"、"怎么理解"、"本质"、"核心"、"逻辑" 出现频率高
   *   emotional:  "怎么做"、"给范例"、"改一下"、"示范" 出现频率高
   *   mixed:     两种模式交替出现，或数据不足
   */
  inferCognitiveStyle(): { style: CognitiveStyle; confidence: number } {
    // 查询所有用户消息
    const userMessages = this.db.prepare(
      "SELECT content FROM messages WHERE role = 'user' ORDER BY timestamp ASC",
    ).all() as { content: string }[];

    if (userMessages.length < MIN_MESSAGES_FOR_STYLE) {
      return { style: 'mixed', confidence: 0 };
    }

    // 关键词统计
    const analyticalKeywords = ['为什么', '怎么理解', '本质', '核心', '逻辑', '意义', '深层', '框架', '方向', '理念'];
    const emotionalKeywords = ['怎么做', '给范例', '改一下', '示范', '具体', '操作', '模板', '步骤', '练习', '例子'];

    let analyticalScore = 0;
    let emotionalScore = 0;

    for (const msg of userMessages) {
      const content = msg.content;
      for (const kw of analyticalKeywords) {
        if (content.includes(kw)) analyticalScore++;
      }
      for (const kw of emotionalKeywords) {
        if (content.includes(kw)) emotionalScore++;
      }
    }

    const total = analyticalScore + emotionalScore;
    if (total === 0) return { style: 'mixed', confidence: 0 };

    const analyticalRatio = analyticalScore / total;

    if (analyticalRatio >= ANALYTICAL_THRESHOLD) {
      return { style: 'analytical', confidence: analyticalRatio };
    }
    if (analyticalRatio <= EMOTIONAL_THRESHOLD) {
      return { style: 'emotional', confidence: 1 - analyticalRatio };
    }
    return { style: 'mixed', confidence: 0.5 };
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
    lines.push(`- 用户画像：${proficiencyMap[proficiency.level]}，${styleMap[cognitiveStyle.style]}`);

    // 2. 反复出现的问题
    const persistentProblems = Object.entries(profile)
      .filter(([, agg]) => agg.occurrenceCount >= MIN_OCCURRENCE_FOR_PERSISTENT)
      .map(([id]) => SYNDROME_NAMES[id] ?? id);

    if (persistentProblems.length > 0) {
      const sessionCount = new Set(
        Object.values(profile).flatMap(a => a.sessionIds),
      ).size;
      lines.push(`- 反复出现的问题：${persistentProblems.join('、')}（跨 ${sessionCount} 次对话）`);
    }

    // 3. 正在改善 / 恶化的信号
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

    return lines.join('\n');
  }

  /**
   * 获取症候名称
   */
  getSyndromeName(id: string): string {
    return SYNDROME_NAMES[id] ?? id;
  }
}
