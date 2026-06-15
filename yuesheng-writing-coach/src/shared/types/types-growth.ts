// 成长与能力画像类型

/** 能力评分 */
export interface AbilityScore {
  abilityId: string;
  abilityName: string;
  score: number;
  relatedSyndromes: string[];
  severityHistory: number[];
  trend: 'up' | 'down' | 'stable';
  dataInsufficient: boolean;
}

/** 弱点标签 */
export interface WeakPoint {
  syndromeId: string;
  syndromeName: string;
  occurrenceCount: number;
  avgSeverity: number;
  lastOccurrence: string;
  trend: 'improving' | 'worsening' | 'stable';
}

/** 训练统计 */
export interface TrainingStats {
  totalAssigned: number;
  totalCompleted: number;
  completionRate: number;
  bySyndrome: Record<string, { assigned: number; completed: number }>;
}

/** 诊断趋势 */
export interface DiagnosisTrend {
  totalDiagnoses: number;
  avgConfidence: number;
  syndromeFrequency: Record<string, number>;
}

/** 能力画像 */
export interface AbilityProfile {
  sessionId: string;
  abilities: AbilityScore[];
  weakPoints: WeakPoint[];
  trainingStats: TrainingStats;
  diagnosisTrend: DiagnosisTrend;
  computedAt: string;
}

/** 新用户引导基线数据 */
export interface OnboardingBaseline {
  /** 写作类型 */
  writingType: 'fantasy' | 'urban' | 'sci-fi' | 'realistic' | 'historical' | 'other' | 'unknown';
  /** 用户发送的示例文字（可选） */
  sampleText?: string;
  /** AI 分析回复摘要 */
  analysisSummary?: string;
  /** 用户选择的改进目标 */
  improvementGoal?: string;
  /** 记录时间戳 */
  capturedAt: number;
}

/** 能力轨迹点 */
export interface TrajectoryPoint {
  date: string;
  score: number;
  eventId: string;
}

/** 成长链事件 */
export interface GrowthEvent {
  eventType: 'diagnosis' | 'training' | 'evaluation';
  eventId: string;
  date: string;
  severity?: 'L1' | 'L2' | 'L3';
  snapshotId?: string;
  sampleText?: string;
  evidenceIds?: string[];
  exerciseId?: string;
  description?: string;
  score?: number;
}

/** 成长链 */
export interface GrowthChain {
  chainId: string;
  abilityId: string;
  syndromeId: string;
  status: 'active' | 'improving' | 'resolved' | 'recurred';
  timeline: GrowthEvent[];
  improvement: string;
  scoreFrom: number;
  scoreTo: number;
}

/** 可视化数据 */
export interface VisualizationData {
  type: 'radar' | 'timeline' | 'comparison';
  data: Record<string, unknown>;
}
