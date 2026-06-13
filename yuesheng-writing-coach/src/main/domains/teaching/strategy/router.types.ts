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
  syndromeOverride?: {
    syndromePatternMap: Record<string, string[]>;
  };
}

interface LevelPath {
  description: string;
  phases: PhaseConfig[];
  skipPatterns: string[];
  skipReason: string;
}

export interface PhaseConfig {
  phase: number;
  name: string;
  corePatterns: Array<{ id: string; name: string }>;
}

export interface CoachingTemplatesConfig {
  strategies: CoachingTemplate[];
}

export interface CoachingTemplate {
  id: string;
  triggerConditions: {
    applicableLevels: string[];
    applicableSyndromes: string[];
  };
  steps: Array<{
    order: number;
    action: string;
    description: string;
  }>;
}

export interface UserTypeMapConfig {
  types: Record<string, {
    label: string;
    syndromes: string[];
    recommendedEntry: string;
  }>;
  teachingStyleMap: Record<string, {
    mode: string;
    tone: string;
  }>;
}

export interface SyndromeTypeMapConfig {
  types: Record<string, {
    label: string;
    syndromes: string[];
    recommendedEntry: string;
  }>;
}

// ==============================
// 完整配置快照
// ==============================

export interface RouterConfigs {
  educationTheoryFragments: EducationTheoryFragment[];
  learningPath: LearningPathConfig;
  techniqueSelectionMatrix: {
    syndromePriorityMap: Record<string, string[]>;
    defaultMaxDifficulty: Record<string, number>;
  };
  coachingTemplates: CoachingTemplatesConfig;
  userTypeMap: UserTypeMapConfig;
  syndromeTypeMap: SyndromeTypeMapConfig;
}
