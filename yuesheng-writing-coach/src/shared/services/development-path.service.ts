/**
 * DevelopmentPathService — Sprint 26 阶段 3.4 Z-1 跨端版
 *
 * 提供发展路径阶段查询,是七阶段发展路径工程化的核心。
 *
 * 与 main/domains/02-prescription/development-path/development-path.service.ts 的关键差异:
 * - **静态 import JSON** 替代 fs.readFileSync(WebView / Android 兼容)
 * - 纯函数式 export,无 fs/path 依赖
 * - 同步 API(getAllStages/getStageById) → 与主进程一致
 * - **不包含** getCurrentStage / checkStageUnlock / calculateStageProgress (依赖 UserMasteryData,需 DB 访问)
 *
 * 适用场景:
 * - Android 端: 静态 import,直接读 JSON
 * - Electron renderer 端: 也可静态 import(无 fs 依赖,只是 Vite 打包 JSON)
 * - Electron 主进程: 仍用原 fs 版(不动,R-021 最小化)
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.4 Z-1
 */
import type {
  DevelopmentStageInfo,
} from '../types/index';
import pathData from '../../../resources/02-prescription/learning-paths/development-path.json';

interface DevelopmentPathJson {
  version: string;
  description: string;
  updatedAt: string;
  stages: StageJsonEntry[];
  metadata: {
    totalStages: number;
    progressionType: string;
    gateType: string;
    gateRule: string;
    flexibilityNote: string;
  };
}

interface StageJsonEntry {
  stageId: string;
  name: string;
  order: number;
  coreQuestion: string;
  prerequisites: string[];
  classicalBasis: Array<{ author: string; principle: string }>;
  entryPractices: string[];
  passCriteria: string;
  associatedSyndromes: string[];
  teachingFocus: string;
}

function toStageInfo(entry: StageJsonEntry): DevelopmentStageInfo {
  return {
    stageId: entry.stageId,
    name: entry.name,
    order: entry.order,
    coreQuestion: entry.coreQuestion,
    prerequisites: entry.prerequisites,
    entryPractices: entry.entryPractices,
    passCriteria: entry.passCriteria,
    associatedSyndromes: entry.associatedSyndromes,
    teachingFocus: entry.teachingFocus,
  };
}

/** 缓存的 stage 列表(模块级单例,首次访问时初始化) */
const stages: DevelopmentStageInfo[] = (pathData as DevelopmentPathJson).stages.map(toStageInfo);

export const developmentPathService = {
  /** 获取所有发展阶段 */
  getAllStages(): DevelopmentStageInfo[] {
    return [...stages];
  },

  /** 按阶段 ID 查询 */
  getStageById(stageId: string): DevelopmentStageInfo | null {
    return stages.find(s => s.stageId === stageId) ?? null;
  },

  /** 按关联症候 ID 查询所属阶段 */
  getStageForSyndrome(syndromeId: string): DevelopmentStageInfo | null {
    return stages.find(s => s.associatedSyndromes.includes(syndromeId)) ?? null;
  },

  /** 按能力大类分类查询阶段 */
  getStagesByCategory(keyword: string): DevelopmentStageInfo[] {
    return stages.filter(s => s.teachingFocus.includes(keyword));
  },
};
