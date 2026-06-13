/**
 * 教学策略路由 — 内部类型定义
 */

// ==============================
// 内部类型：配置 JSON 的 TS 视图
// ==============================

export interface EducationTheoryFragment {
  id: string;
  condition: Record<string, unknown>;
  recommendedMode: string;
  rationale: string;
  source: string;
  priority: string;
}

export interface LearningPathConfig {
  version: string;
  beginner: LevelPath;
  intermediate: LevelPath;
  advanced: LevelPath;
  syndromeOverride: {
    syndromePatternMap: Record<string, string[]>;
  };
}

export interface LevelPath {
  description: string;
  phases: PhaseConfig[];
  skipPatterns: string[];
  skipReason: string;
}

export interface PhaseConfig {
  phase: number;
  name: string;
  corePatterns: Array<{
    id: string;
    reason: string;
    maxDifficultyOrder: number;
  }>;
  maxTechniquesPerPattern: number;
}

export interface TechniqueSelectionMatrix {
  syndromePriorityMap: Record<string, string[]>;
  defaultMaxDifficulty: Record<string, {
    maxDifficultyOrder: number;
    override?: Record<string, { maxDifficultyOrder?: number; skip?: boolean }>;
  }>;
}

export interface CoachingTemplate {
  id: string;
  name: string;
  triggerConditions: {
    applicableLevels: string[];
    applicableSyndromes: string[];
  };
  steps: Array<{
    order: number;
    action: string;
    template: string;
  }>;
  contraindications: string[];
}

export interface CoachingTemplatesConfig {
  strategies: CoachingTemplate[];
}

export interface UserTypeMapConfig {
  types: Record<string, {
    name: string;
    teachingStyle?: string;
    applicableRules?: string[];
  }>;
  teachingStyleMap: Record<string, {
    mode: string;
    tone: string;
    challengeSize: string;
  }>;
}

export interface SyndromeTypeMapConfig {
  types: Record<string, {
    name: string;
    syndromes: string[];
    recommendedEntry: string;
    rationale: string;
  }>;
}

/** 运行时的全部已加载配置快照 */
export interface RouterConfigs {
  educationTheoryFragments: EducationTheoryFragment[];
  learningPath: LearningPathConfig;
  techniqueSelectionMatrix: TechniqueSelectionMatrix;
  coachingTemplates: CoachingTemplatesConfig;
  userTypeMap: UserTypeMapConfig;
  syndromeTypeMap: SyndromeTypeMapConfig;
}
