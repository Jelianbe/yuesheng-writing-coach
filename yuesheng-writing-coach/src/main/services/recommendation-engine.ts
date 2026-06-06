/**
 * Personalized Recommendation Engine Service
 * 
 * 根据用户诊断结果、画像和训练进度推荐个性化训练任务
 * 从训练任务库中匹配最适合的任务
 * 
 * @module services/recommendation-engine
 * @phase Phase 2（MVP 后实现，当前为类型骨架）
 */

export interface TrainingRecord {
  taskId: string;
  completedAt: string;
  score?: number;
}

export interface StudentProfile {
  studentType: string;
  totalSessions: number;
  strengths: string[];
  weaknesses: string[];
  trainingHistory: TrainingRecord[];
}

export interface DiagnosisResult {
  syndromes: Array<{ syndromeId: string; score: number }>;
  suggestedActions: Array<{ actionId: string; priority: number }>;
}

export interface TaskRecommendation {
  taskId: string;
  taskName: string;
  priority: number;             // 1-10
  matchScore: number;           // 0-1
  targetSyndrome?: string;
  difficulty: 'beginner' | 'intermediate' | 'advanced';
  estimatedTime: number;        // 分钟
  description: string;
  expectedOutcome: string;
}

export interface RecommendationResult {
  recommendations: TaskRecommendation[];
  reasoning: string;
  nextMilestone?: string;
  estimatedTime?: number;
  timestamp: string;
}

export interface RecommendationContext {
  recentFocus?: string;
  userPreference?: string;
  timeConstraint?: number;
}

export interface RecommendationConfig {
  maxRecommendations: number;
  minMatchScore: number;
  weights: {
    syndromeMatch: number;
    difficultyMatch: number;
    historyMatch: number;
    preferenceMatch: number;
  };
  difficultyRules: {
    novice: { maxSessions: number; difficulty: 'beginner' };
    intermediate: { maxSessions: number; difficulty: 'intermediate' };
    advanced: { minSessions: number; difficulty: 'advanced' };
  };
}

const DEFAULT_CONFIG: RecommendationConfig = {
  maxRecommendations: 3,
  minMatchScore: 0.5,
  weights: {
    syndromeMatch: 0.4,
    difficultyMatch: 0.2,
    historyMatch: 0.2,
    preferenceMatch: 0.2,
  },
  difficultyRules: {
    novice: { maxSessions: 5, difficulty: 'beginner' },
    intermediate: { maxSessions: 20, difficulty: 'intermediate' },
    advanced: { minSessions: 20, difficulty: 'advanced' },
  },
};

/**
 * 病症到训练任务的映射
 */
const SYNDROME_TASK_MAP: Record<string, { taskId: string; priority: number }> = {
  'P001': { taskId: 'T001', priority: 9 },
  'P002': { taskId: 'T003', priority: 9 },
  'P003': { taskId: 'T005', priority: 7 },
  'P004': { taskId: 'T007', priority: 9 },
  'P005': { taskId: 'T009', priority: 7 },
  'P006': { taskId: 'T011', priority: 7 },
  'P007': { taskId: 'T013', priority: 5 },
  'P009': { taskId: 'T017', priority: 8 },
  'P010': { taskId: 'T019', priority: 7 },
};

/**
 * 聚焦方向优先关注的症候列表
 */
const FOCUS_AREA_SYNDROMES: Record<string, string[]> = {
  worldbuilding: ['P001', 'P004'],
  character: ['P002', 'P009', 'P010'],
  general: [],
};

/**
 * 推荐训练任务
 * @param diagnosisResult 诊断结果（可选）
 * @param studentProfile 用户画像
 * @param context 推荐上下文
 * @param config 推荐配置
 * @param focusArea 聚焦方向（可选）
 */
export async function recommendTasks(
  studentProfile: StudentProfile,
  diagnosisResult?: DiagnosisResult,
  context?: RecommendationContext,
  config: Partial<RecommendationConfig> = {},
  focusArea?: string | null,
): Promise<RecommendationResult> {
  const mergedConfig = { ...DEFAULT_CONFIG, ...config };

  // TODO: 实现推荐逻辑
  // 1. 加载训练任务库
  // 2. 排除已完成任务
  // 3. 根据病症筛选候选任务
  // 4. 计算匹配度
  // 5. 按 focusArea 排序并选择 Top N

  return {
    recommendations: [],
    reasoning: focusArea ? `按 ${focusArea} 优先排序` : '待实现',
    timestamp: new Date().toISOString(),
  };
}

/**
 * 根据 focusArea 对推荐结果排序
 * 相关症候的训练任务优先排在前面
 */
export function sortByFocusArea(
  recommendations: TaskRecommendation[],
  focusArea?: string | null,
): TaskRecommendation[] {
  if (!focusArea || focusArea === 'general') {
    return recommendations;
  }

  const prioritySyndromes = FOCUS_AREA_SYNDROMES[focusArea] || [];
  return [...recommendations].sort((a, b) => {
    const aPriority = a.targetSyndrome && prioritySyndromes.includes(a.targetSyndrome) ? 1 : 0;
    const bPriority = b.targetSyndrome && prioritySyndromes.includes(b.targetSyndrome) ? 1 : 0;
    return bPriority - aPriority;
  });
}

/**
 * 计算任务匹配度
 */
export function calculateMatchScore(
  syndromeScore: number,
  difficultyMatch: number,
  historyScore: number,
  preferenceScore: number,
  weights: RecommendationConfig['weights'],
): number {
  return (
    syndromeScore * weights.syndromeMatch +
    difficultyMatch * weights.difficultyMatch +
    historyScore * weights.historyMatch +
    preferenceScore * weights.preferenceMatch
  );
}

/**
 * 根据会话数判定难度
 */
export function getDifficultyForSessions(totalSessions: number, rules: RecommendationConfig['difficultyRules']): 'beginner' | 'intermediate' | 'advanced' {
  if (totalSessions <= rules.novice.maxSessions) {
    return 'beginner';
  } else if (totalSessions <= rules.intermediate.maxSessions) {
    return 'intermediate';
  }
  return 'advanced';
}
