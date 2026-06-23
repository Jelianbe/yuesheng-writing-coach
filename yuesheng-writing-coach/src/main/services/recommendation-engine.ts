/**
 * Personalized Recommendation Engine Service
 * 
 * 根据用户诊断结果、画像和训练进度推荐个性化训练任务
 * 从训练任务库中匹配最适合的任务
 * 
 * @module services/recommendation-engine
 */

import challengeTemplates from '../../../resources/04-validation/mastery/challenge-templates.json';
import techniqueLibrary from '../../../resources/config/technique-library.json';

// ===== 类型定义 =====

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
  priority: number;
  matchScore: number;
  targetSyndrome?: string;
  difficulty: 'beginner' | 'intermediate' | 'advanced';
  estimatedTime: number;
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

const FOCUS_AREA_SYNDROMES: Record<string, string[]> = {
  worldbuilding: ['P001', 'P004'],
  character: ['P002', 'P009', 'P010'],
  general: [],
};

// 挑战模板 JSON 类型
interface ChallengeTemplate {
  id: string;
  syndromeId: string;
  syndromeName: string;
  challenge: string;
  mode: string;
  tier: string;
  constraint: string;
  expectedOutcome: string;
}

interface ChallengeTemplatesJson {
  templates: ChallengeTemplate[];
  fallbackChallenge: {
    challenge: string;
    mode: string;
    description: string;
  };
}

const templates = challengeTemplates as unknown as ChallengeTemplatesJson;

// 技法库类型
interface TechniqueEntry {
  id: string;
  name: string;
  difficulty: string;
  applicableSyndromes: string[];
  description: string;
  example: string;
}

const techniques = techniqueLibrary as unknown as TechniqueEntry[];

/**
 * 推荐训练任务
 * 根据诊断结果和用户画像，从训练任务库中匹配最高优先级的任务。
 */
export async function recommendTasks(
  studentProfile: StudentProfile,
  diagnosisResult?: DiagnosisResult,
  _context?: RecommendationContext,
  config: Partial<RecommendationConfig> = {},
  focusArea?: string | null,
): Promise<RecommendationResult> {
  const mergedConfig = { ...DEFAULT_CONFIG, ...config };

  // 1. 确定难度等级
  const difficulty = getDifficultyForSessions(studentProfile.totalSessions, mergedConfig.difficultyRules);

  // 2. 收集待匹配的症候（按诊断得分降序排列）
  const targetSyndromeIds: string[] = [];
  if (diagnosisResult?.syndromes) {
    const sorted = [...diagnosisResult.syndromes]
      .sort((a, b) => b.score - a.score);
    targetSyndromeIds.push(...sorted.map(s => s.syndromeId));
  } else if (studentProfile.weaknesses.length > 0) {
    targetSyndromeIds.push(...studentProfile.weaknesses);
  }

  // 3. 排除已完成的训练任务
  const completedIds = new Set(
    studentProfile.trainingHistory
      .filter(tr => tr.score && tr.score >= 6)
      .map(tr => tr.taskId),
  );

  // 4. 遍历症候→挑战模板匹配，构建推荐列表
  const recommendations: TaskRecommendation[] = [];

  for (const syndromeId of targetSyndromeIds) {
    if (recommendations.length >= mergedConfig.maxRecommendations) break;

    const template = templates.templates.find(t => t.syndromeId === syndromeId);
    const challengeId = template?.id ?? 'CH-FALLBACK';

    if (completedIds.has(challengeId)) continue;

    // 匹配技法（仅用于丰富描述）
    const matchedTechniques = techniques
      .filter(t => t.applicableSyndromes.includes(syndromeId))
      .slice(0, 2);

    // 计算匹配度
    const syndromeScore = 1.0; // 直接命中
    const difficultyMatch = matchedTechniques.some(t => t.difficulty === difficulty) ? 1.0 : 0.5;
    const historyScore = studentProfile.trainingHistory.length === 0 ? 0.3 : 0.7;
    const preferenceScore = focusArea && FOCUS_AREA_SYNDROMES[focusArea]?.includes(syndromeId) ? 1.0 : 0.6;

    const matchScore = calculateMatchScore(
      syndromeScore,
      difficultyMatch,
      historyScore,
      preferenceScore,
      mergedConfig.weights,
    );

    if (matchScore < mergedConfig.minMatchScore) continue;

    const priority = Math.round(matchScore * 10);
    const techniqueDesc = matchedTechniques.length > 0
      ? `推荐技法：${matchedTechniques.map(t => t.name).join('、')}。`
      : '';

    recommendations.push({
      taskId: challengeId,
      taskName: template?.syndromeName ?? syndromeId,
      priority,
      matchScore: Math.round(matchScore * 100) / 100,
      targetSyndrome: syndromeId,
      difficulty,
      estimatedTime: 15,
      description: template?.challenge
        ? `${template.challenge} ${techniqueDesc}`
        : `针对性训练：解决 "${syndromeId}" 问题。${techniqueDesc}`,
      expectedOutcome: template?.expectedOutcome ?? '改善该症候',
    });
  }

  // 5. 按优先级排序
  recommendations.sort((a, b) => b.priority - a.priority);

  // 6. 按 focusArea 排序
  const sorted = sortByFocusArea(recommendations, focusArea);

  return {
    recommendations: sorted.slice(0, mergedConfig.maxRecommendations),
    reasoning: focusArea
      ? `按 "${focusArea}" 方向优先排序，匹配 ${recommendations.length} 项推荐`
      : `基于 ${targetSyndromeIds.length} 个活跃症候生成 ${recommendations.length} 项推荐`,
    estimatedTime: sorted.length * 15,
    timestamp: new Date().toISOString(),
  };
}

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

export function getDifficultyForSessions(
  totalSessions: number,
  rules: RecommendationConfig['difficultyRules'],
): 'beginner' | 'intermediate' | 'advanced' {
  if (totalSessions <= rules.novice.maxSessions) {
    return 'beginner';
  } else if (totalSessions <= rules.intermediate.maxSessions) {
    return 'intermediate';
  }
  return 'advanced';
}
