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
 */

import { ActiveProblem, TrainingRecommendation, TechniqueInfo, SyndromeType } from '../../renderer/shared/types';
import challengeTemplates from '../../../resources/config/challenge-templates.json';
import techniqueLibrary from '../../../resources/config/technique-library.json';
import syndromeTypeMap from '../../../resources/config/syndrome-type-map.json';

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
  return sorted.map((problem) => {
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
