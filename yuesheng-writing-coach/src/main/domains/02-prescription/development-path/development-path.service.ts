/**
 * 发展路径服务（DevelopmentPathService）
 *
 * 职责：加载 development-path.json，提供阶段查询、用户当前阶段判定、
 * 阶段解锁条件检查等能力，是七阶段发展路径工程化的核心。
 *
 * 设计原则：
 * - 惰性加载：首次使用时读取 JSON
 * - 纯查询：不修改用户数据，只基于传入的 masteryData 做计算
 * - 无外部依赖：不引入循环依赖
 *
 * MasteryGate 规则：
 * - 当前阶段所有关联症候的平均评分 > 80%（即 score > 8/10）才能解锁下一阶段
 * - 无关联症候的阶段视为自动通过
 */

import * as fs from 'fs';
import * as path from 'path';

import type { DevelopmentStageInfo, UserMasteryData, StageProgress } from '../../../../shared/types/index';

// ==============================
// 内部类型
// ==============================

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

// ==============================
// 常量
// ==============================

const JSON_PATH = path.resolve(__dirname, '../../../../../resources/02-prescription/learning-paths/development-path.json');

/** MasteryGate 通过阈值：平均评分 >= 8（即 80%） */
const MASTERY_GATE_THRESHOLD = 8;

// ==============================
// 内部状态
// ==============================

let cachedData: DevelopmentPathJson | null = null;
let cachedStages: DevelopmentStageInfo[] | null = null;
let loaded = false;

// ==============================
// 内部方法
// ==============================

function loadJson(): void {
  if (loaded) return;
  try {
    const raw = fs.readFileSync(JSON_PATH, 'utf-8');
    cachedData = JSON.parse(raw) as DevelopmentPathJson;
  } catch (err) {
    console.warn('[DevelopmentPathService] Failed to load development-path.json:', err);
    cachedData = {
      version: '',
      description: '',
      updatedAt: '',
      stages: [],
      metadata: {
        totalStages: 0,
        progressionType: '',
        gateType: '',
        gateRule: '',
        flexibilityNote: '',
      },
    };
  }

  cachedStages = cachedData.stages.map(toStageInfo);
  loaded = true;
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

function ensureLoaded(): void {
  if (!loaded) loadJson();
}

/**
 * 计算单个症候的平均评分
 * 取最近 N 次评分的平均值
 */
function calculateMastery(syndromeId: string, masteryData: UserMasteryData[]): number {
  const data = masteryData.find(m => m.syndromeId === syndromeId);
  if (!data || data.trainingCount === 0) return 0;
  return data.averageScore;
}

/**
 * 判断一个阶段是否已通过（所有关联症候的 MasteryGate 达标）
 */
function isStagePassed(stage: DevelopmentStageInfo, masteryData: UserMasteryData[]): boolean {
  if (stage.associatedSyndromes.length === 0) return true;
  return stage.associatedSyndromes.every(sid => calculateMastery(sid, masteryData) >= MASTERY_GATE_THRESHOLD);
}

/**
 * 获取未通过的症候列表
 */
function getBlockingSyndromes(stage: DevelopmentStageInfo, masteryData: UserMasteryData[]): string[] {
  if (stage.associatedSyndromes.length === 0) return [];
  return stage.associatedSyndromes.filter(sid => calculateMastery(sid, masteryData) < MASTERY_GATE_THRESHOLD);
}

// ==============================
// 公开 API
// ==============================

/**
 * 获取所有发展阶段
 */
export function getAllStages(): DevelopmentStageInfo[] {
  ensureLoaded();
  return [...cachedStages!];
}

/**
 * 按阶段 ID 查询
 */
export function getStageById(stageId: string): DevelopmentStageInfo | undefined {
  ensureLoaded();
  return cachedStages!.find(s => s.stageId === stageId);
}

/**
 * 按关联症候 ID 查询所属阶段
 */
export function getStageForSyndrome(syndromeId: string): DevelopmentStageInfo | undefined {
  ensureLoaded();
  return cachedStages!.find(s => s.associatedSyndromes.includes(syndromeId));
}

/**
 * 按能力大类分类查询阶段（根据 teachingFocus 关键词匹配）
 */
export function getStagesByCategory(keyword: string): DevelopmentStageInfo[] {
  ensureLoaded();
  return cachedStages!.filter(s => s.teachingFocus.includes(keyword));
}

/**
 * 获取用户当前阶段及进度
 *
 * 逻辑：从第一阶段开始遍历，找到第一个未通过的阶段即为当前阶段。
 * 如果所有阶段都通过，则为最终阶段。
 *
 * @param masteryData - 用户在各症候上的掌握度数据
 * @returns 阶段进度信息
 */
export function getCurrentStage(masteryData: UserMasteryData[]): StageProgress {
  ensureLoaded();

  const stages = cachedStages!;

  // 按 order 排序
  const sorted = [...stages].sort((a, b) => a.order - b.order);

  // 找到第一个未通过或处于边界状态的阶段
  let currentIndex = 0;
  for (let i = 0; i < sorted.length; i++) {
    const stage = sorted[i];
    const passed = isStagePassed(stage, masteryData);

    if (!passed) {
      currentIndex = i;
      break;
    }

    // 检查前置阶段是否通过
    if (i === sorted.length - 1) {
      // 最后一阶段也通过了 — 全部完成
      currentIndex = i;
    } else {
      // 当前阶段通过，继续检查下一阶段
      currentIndex = i + 1;
    }
  }

  const currentStage = sorted[currentIndex];
  const isLastStage = currentIndex >= sorted.length - 1;
  const nextStage = isLastStage ? undefined : sorted[currentIndex + 1];

  // 计算当前阶段进度
  const progress = calculateStageProgress(currentStage, masteryData);

  // 判断当前阶段是否已解锁
  const stageUnlocked = checkStageUnlock(currentStage.stageId, masteryData);

  // 检查下一阶段是否可解锁
  let nextStageUnlockable: boolean | undefined;
  if (nextStage) {
    nextStageUnlockable = isStagePassed(currentStage, masteryData);
  }

  // 阻碍因素
  const blockingSyndromes = getBlockingSyndromes(currentStage, masteryData);

  return {
    currentStage,
    progress,
    nextStage,
    stageUnlocked,
    nextStageUnlockable: nextStage ? nextStageUnlockable : undefined,
    blockingSyndromes: blockingSyndromes.length > 0 ? blockingSyndromes : undefined,
  };
}

/**
 * 检查指定阶段是否已解锁（前置条件满足）
 */
export function checkStageUnlock(stageId: string, masteryData: UserMasteryData[]): boolean {
  ensureLoaded();
  const stage = cachedStages!.find(s => s.stageId === stageId);
  if (!stage) return false;

  // 第一阶段无条件解锁
  if (stage.prerequisites.length === 0) return true;

  // 检查所有前置阶段是否通过
  for (const prereqId of stage.prerequisites) {
    const prereqStage = cachedStages!.find(s => s.stageId === prereqId);
    if (!prereqStage) return false;
    if (!isStagePassed(prereqStage, masteryData)) return false;
  }

  return true;
}

/**
 * 计算指定阶段的进度百分比
 *
 * 逻辑：关联症候的平均评分映射到 0-100%
 * - 0 个症候 → 视为 100%
 * - 否则取平均值 / MASTERY_GATE_THRESHOLD * 100，上限 100%
 */
export function calculateStageProgress(stage: DevelopmentStageInfo, masteryData: UserMasteryData[]): number {
  if (stage.associatedSyndromes.length === 0) return 100;

  let total = 0;
  for (const sid of stage.associatedSyndromes) {
    total += calculateMastery(sid, masteryData);
  }
  const avg = total / stage.associatedSyndromes.length;
  return Math.min(100, Math.round((avg / MASTERY_GATE_THRESHOLD) * 100));
}

/**
 * 获取 MasteryGate 通过阈值
 */
export function getMasteryThreshold(): number {
  return MASTERY_GATE_THRESHOLD;
}

/**
 * 重新加载数据
 */
export function reload(): void {
  loaded = false;
  cachedData = null;
  cachedStages = null;
  loadJson();
}

/** 检查是否已加载 */
export function isLoaded(): boolean {
  return loaded;
}
