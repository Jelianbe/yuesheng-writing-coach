/**
 * 训练推荐服务
 *
 * 职责：根据当前活跃症候和挑战模板，生成训练推荐列表
 *
 * 推荐策略：
 * 1. 只推荐 L2+ 严重度的症候（L1 视为已改善，无需训练）
 * 2. 按严重度排序（L3 > L2），同严重度按症候 ID 排序
 * 3. 每个活跃症候匹配一个挑战模板（syndromeId 一对一映射）
 * 4. 无匹配模板的症候使用 fallbackChallenge
 *
 * A3 阅读推荐策略：
 * - 当用户训练表现好（评估分数 >= 阈值）时，推荐相关阅读材料
 * - 从 reading-library.json 中选择与当前症候相关的阅读任务
 */

import { ActiveProblem, TrainingRecommendation, TechniqueInfo, SyndromeType } from '../../../shared/types/index';
import challengeTemplates from '../../../../resources/config/challenge-templates.json';
import techniqueLibrary from '../../../../resources/config/technique-library.json';
import syndromeTypeMap from '../../../../resources/config/syndrome-type-map.json';
import readingLibrary from '../../../../resources/config/reading-library.json';

// 类型定义：challenge-templates.json 的结构
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
  source: string;
  difficulty: string;
  category: string;
  applicableSyndromes: string[];
  description: string;
  example: string;
}

const techniques = techniqueLibrary as unknown as TechniqueEntry[];

// 症候类型映射 JSON 结构
interface SyndromeTypeEntry {
  name: string;
  syndromes: string[];
  discoverable?: boolean | string;
  coreIssue: string;
  recommendedEntry: string;
  rationale: string;
}

interface SyndromeTypeMapJson {
  version: string;
  updatedAt: string;
  types: Record<string, SyndromeTypeEntry>;
}

const typeMap = syndromeTypeMap as unknown as SyndromeTypeMapJson;

/**
 * 获取症候所属类型（用于教育学规则匹配）
 * @param syndromeId - 症候 ID
 * @returns 症候类型或 null（未找到时）
 */
export function getSyndromeType(syndromeId: string): SyndromeType | null {
  for (const [type, info] of Object.entries(typeMap.types)) {
    if (info.syndromes.includes(syndromeId)) {
      return type as SyndromeType;
    }
  }
  return null;
}

/**
 * 根据症候 ID 匹配技法（最多 3 条，按难度排序）
 */
function matchTechniques(syndromeId: string): TechniqueInfo[] {
  const matched = techniques
    .filter(t => t.applicableSyndromes.includes(syndromeId))
    .sort((a, b) => {
      const order: Record<string, number> = { beginner: 0, intermediate: 1, advanced: 2 };
      return (order[a.difficulty] ?? 3) - (order[b.difficulty] ?? 3);
    })
    .slice(0, 3);

  return matched.map(t => ({
    id: t.id,
    name: t.name,
    source: t.source,
    difficulty: t.difficulty,
    category: t.category,
    description: t.description,
    example: t.example,
  }));
}

/**
 * 根据活跃症候生成训练推荐列表
 *
 * @param activeProblems - 当前活跃症候列表
 * @returns 推荐训练任务列表（按严重度排序）
 */
export function generateRecommendations(
  activeProblems: ActiveProblem[],
): TrainingRecommendation[] {
  const fallback = templates.fallbackChallenge;

  // 过滤 L2+ 的症候
  const eligible = activeProblems.filter(
    (p) => p.severity === 'L2' || p.severity === 'L3',
  );

  // 按严重度排序（L3 优先）
  const severityOrder: Record<string, number> = { L3: 0, L2: 1, L1: 2 };
  const sorted = [...eligible].sort((a, b) => {
    const diff = severityOrder[a.severity] - severityOrder[b.severity];
    if (diff !== 0) return diff;
    return a.id.localeCompare(b.id);
  });

  // 为每个症候生成推荐
  const raw = sorted.map((problem) => {
    const matchedTemplate = templates.templates.find(
      (t) => t.syndromeId === problem.id,
    );

    if (matchedTemplate) {
      return {
        challengeId: matchedTemplate.id,
        challengeName: matchedTemplate.syndromeName,
        description: matchedTemplate.challenge,
        syndromeId: problem.id,
        syndromeType: getSyndromeType(problem.id),
        severity: problem.severity,
        tier: matchedTemplate.tier,
        constraint: matchedTemplate.constraint,
        expectedOutcome: matchedTemplate.expectedOutcome,
        mode: matchedTemplate.mode,
        techniques: matchTechniques(problem.id),
      };
    }

    // 无匹配模板，使用 fallback
    return {
      challengeId: 'CH-FALLBACK',
      challengeName: problem.name,
      description: fallback.challenge,
      syndromeId: problem.id,
      syndromeType: getSyndromeType(problem.id),
      severity: problem.severity,
      tier: 'surface',
      constraint: '',
      expectedOutcome: '改善该症候',
      mode: fallback.mode,
      techniques: matchTechniques(problem.id),
    };
  });

  // 去重：基于 challengeId 去重；fallback 项挑战内容相同，只保留首个
  const seen = new Set<string>();
  const deduped = raw.filter((rec) => {
    const key = rec.challengeId;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

  // 确保至少 3 个推荐：去重后不足时回退到原始列表
  if (deduped.length < 3 && raw.length >= 3) {
    return raw.slice(0, Math.max(3, deduped.length));
  }

  return deduped;
}

/**
 * 根据挑战 ID 获取模板详情
 */
export function getChallengeTemplate(challengeId: string): ChallengeTemplate | null {
  const template = templates.templates.find((t) => t.id === challengeId);
  return template ?? null;
}

/**
 * 获取所有挑战模板
 */
export function getAllChallengeTemplates(): ChallengeTemplate[] {
  return [...templates.templates];
}

// ======================== A3 阅读推荐 ========================

/** 阅读库条目类型（来自 reading-library.json） */
interface ReadingEntry {
  id: string;
  source: string;
  createdAt: string;
  syndromeId: string;
  principleAnchor: string;
  title: string;
  excerpt: string;
  analysisPrompt: string;
  referenceExcerpt?: string | null;
  difficulty: string;
  tags: string[];
  categoryId: string;
}

/** 阅读库 JSON 结构 */
interface ReadingLibraryJson {
  $source: string;
  description: string;
  version: string;
  updatedAt: string;
  readingSteps: {
    source: string;
    steps: Array<{ id: string; title: string; description: string }>;
  };
  categories: Array<{
    id: string;
    name: string;
    description: string;
    tags: string[];
  }>;
  entries: ReadingEntry[];
}

/** A3 阅读推荐阈值：评估分数 >= 此值时触发阅读推荐 */
export const READING_RECOMMENDATION_THRESHOLD = 7;

/** A3 阅读推荐条目（供前端消费） */
export interface ReadingRecommendation {
  /** 阅读条目 ID */
  id: string;
  /** 标题 */
  title: string;
  /** 症候 ID */
  syndromeId: string;
  /** 难度 */
  difficulty: string;
  /** 分类 ID */
  categoryId: string;
  /** 标签 */
  tags: string[];
  /** 选段 */
  excerpt: string;
  /** 分析引导 */
  analysisPrompt: string;
  /** 参考引言（可选） */
  referenceExcerpt?: string | null;
}

const library = readingLibrary as unknown as ReadingLibraryJson;

/**
 * A3: 根据症候 ID 获取阅读推荐
 *
 * @param syndromeId - 当前训练的症候 ID
 * @returns 匹配的阅读推荐列表（最多 3 条）
 */
export function getReadingRecommendations(syndromeId: string): ReadingRecommendation[] {
  if (!library.entries || !Array.isArray(library.entries)) {
    return [];
  }

  const matched = library.entries
    .filter((e) => e.syndromeId === syndromeId)
    .slice(0, 3)
    .map((e) => ({
      id: e.id,
      title: e.title,
      syndromeId: e.syndromeId,
      difficulty: e.difficulty,
      categoryId: e.categoryId,
      tags: e.tags,
      excerpt: e.excerpt,
      analysisPrompt: e.analysisPrompt,
      referenceExcerpt: e.referenceExcerpt,
    }));

  return matched;
}

/**
 * A3: 判断是否应该推荐阅读
 *
 * @param evaluationScore - 用户训练评估分数（0-10）
 * @returns 是否达到阅读推荐阈值
 */
export function shouldRecommendReading(evaluationScore: number | undefined): boolean {
  if (evaluationScore == null) return false;
  return evaluationScore >= READING_RECOMMENDATION_THRESHOLD;
}
