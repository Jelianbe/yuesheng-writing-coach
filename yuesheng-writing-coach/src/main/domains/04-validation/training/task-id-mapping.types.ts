/**
 * Task ID Mapping — 类型定义
 *
 * 对应 resources/config/task-id-mapping.json 的结构
 *
 * 三向映射体系：
 * - T0XX：能力图谱任务（resources/knowledge-graph/ability-atlas.json）
 * - TRAIN-PXXX：教学处方任务（resources/02-prescription/training-library.json）
 * - CH-PXXX：挑战式微练（resources/04-validation/mastery/challenge-templates.json）
 */

/** T0XX → TRAIN-PXXX 映射规则（单条） */
export interface T0XXToTrainMapping {
  syndrome: string;
  type: string;
  difficulty: number;
  /** 目标 TRAIN-PXXX ID；无匹配时为 'TBD' */
  mapsTo: string;
  rationale: string;
}

/** TRAIN-PXXX → CH-PXXX 映射规则（单条） */
export interface TrainToChallengeMapping {
  syndrome: string;
  relatedChallenges: string[];
  rationale: string;
}

/** PRAC-XXX 通用任务关联症候 */
export interface PracToSyndromeMapping {
  primarySyndrome: string;
  rationale: string;
}

/** 孤儿项追踪 */
export interface OrphanTracking {
  orphanT0XX: Array<{ id: string; reason: string; action?: string }>;
  orphanTRAIN: Array<{ id: string; reason: string }>;
  orphanCH: Array<{ id: string; reason: string }>;
  orphanSyndromes: Array<{
    id: string;
    name: string;
    presentIn: { T0XX: boolean; TRAIN_PXXX: boolean; CH_PXXX: boolean };
    action: string;
  }>;
}

/** Task ID Mapping JSON 根结构 */
export interface TaskIdMappingJson {
  $schema: string;
  $source: string;
  description: string;
  version: string;
  generatedAt: string;
  generatedBy: string;
  _meta: {
    primarySource: string;
    sources: {
      T0XX: string;
      TRAIN_PXXX: string;
      CH_PXXX: string;
    };
    matchingRules: string[];
  };
  syndromeMapping: Record<string, {
    T0XX: string[];
    TRAIN_PXXX: string[];
    CH_PXXX: string[];
    _note?: string;
  }>;
  T0XX_to_TRAIN: Record<string, T0XXToTrainMapping>;
  TRAIN_to_T0XX: Record<string, string | null>;
  TRAIN_to_CH: Record<string, TrainToChallengeMapping>;
  CH_to_TRAIN: Record<string, string[]>;
  PRAC_to_syndrome: Record<string, PracToSyndromeMapping>;
  orphanTracking: OrphanTracking;
  statistics: {
    T0XX: number;
    TRAIN_PXXX: number;
    TRAIN_PXXX_general: number;
    CH_PXXX: number;
    syndromesCovered: number;
    orphanSyndromes: number;
    orphanT0XX: number;
    orphanTRAIN: number;
    orphanCH: number;
  };
}
