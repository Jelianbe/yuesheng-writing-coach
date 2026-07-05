/**
 * 学生模型服务 — 类型定义、常量与关键词体系
 *
 * 设计依据：
 *   - student-model-redesign_V1.0.md §2.2 StudentModel 数据结构
 *   - SPEC_adaptive-teaching_V1.0.md §3 学生模型
 */

import type { SeverityLevel } from '../../../../shared/types/index';

export type { SeverityLevel };

// ============ 能力等级判定阈值 ============

/** L3 出现 ≥ 此值 → beginner */
export const MIN_L3_FOR_BEGINNER = 3;
/** L2 出现 ≥ 此值 → beginner */
export const MIN_L2_FOR_BEGINNER = 5;
/** 最近 N 次诊断窗口 */
export const RECENT_WINDOW = 5;
/** 最近 N 次全是 L1 → advanced */
export const MIN_RECENT_FOR_ADVANCED = 5;
/** 置信度默认除数 */
export const DEFAULT_CONFIDENCE_DIVISOR = 10;

/** 认知风格判定所需最少消息数（入场诊断） */
export const MIN_MESSAGES_FOR_STYLE = 2;
/** 入场诊断置信度缩放（消息不足时） */
export const MIN_STYLE_CONFIDENCE_SCALE = 0.5;
/** 分析型比例 ≥ 此值 → analytical */
export const ANALYTICAL_THRESHOLD = 0.6;
/** 情感型比例 ≤ 此值 → emotional */
export const EMOTIONAL_THRESHOLD = 0.4;
/** 最近消息权重系数 */
export const RECENCY_WEIGHT = 1.5;
/** 旧消息权重系数 */
export const HISTORY_WEIGHT = 0.5;
/** 最近消息窗口 */
export const RECENCY_WINDOW = 3;
/** 强信号关键词权重 */
export const TIER_1_WEIGHT = 2;
/** 弱信号关键词权重 */
export const TIER_3_WEIGHT = 0.5;

/** 分层关键词体系 — 分析型 */
export const ANALYTICAL_KEYWORDS: Array<{ words: string[]; tier: 1 | 2 | 3 }> = [
  { tier: 1, words: ['结构', '因果关系', '逻辑关系', '对比', '层次', '一致性'] },
  { tier: 2, words: ['为什么', '怎么理解', '本质', '核心', '逻辑', '意义', '深层', '框架', '方向', '理念', '分析', '系统', '论证', '批判'] },
  { tier: 3, words: ['定义', '规律', '模式', '分类', '推理', '原由', '机制'] },
];

/** 分层关键词体系 — 情感型 */
export const EMOTIONAL_KEYWORDS: Array<{ words: string[]; tier: 1 | 2 | 3 }> = [
  { tier: 1, words: ['感觉', '共鸣', '打动', '代入', '沉浸', '氛围'] },
  { tier: 2, words: ['怎么做', '给范例', '改一下', '示范', '体验', '情感', '冲突', '生动', '感染力', '细腻'] },
  { tier: 3, words: ['故事', '共鸣点', '场景', '对话', '人物', '情绪', '温度'] },
];

/** 反复出现问题的发生次数阈值 */
export const MIN_OCCURRENCE_FOR_PERSISTENT = 3;
/** 停滞判定所需最小会话数 */
export const MIN_SESSION_FOR_STAGNATION = 3;
/** 训练完成率 ≥ 此值 → 成熟 */
export const TRAINING_COMPLETION_FOR_MATURE = 0.6;

// ============ 类型定义 ============

/** 能力等级 */
export type ProficiencyLevel = 'beginner' | 'intermediate' | 'advanced';

/** 认知风格 */
export type CognitiveStyle = 'analytical' | 'emotional' | 'mixed';

/** 训练成熟度 */
export type TrainingMaturity = 'mature' | 'developing' | 'minimal';

/** 症候聚合数据 */
export interface SyndromeAggregation {
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
  /** 熟练度简标签（如 "新手写作者"） */
  proficiencyLabel?: Record<string, string>;
  /** 认知风格简标签（如 "理性分析型"） */
  cognitiveStyleLabel?: Record<string, string>;
  /** 训练成熟度简标签（如 "教学适应度高"） */
  trainingMaturityLabel?: Record<string, string>;
}
