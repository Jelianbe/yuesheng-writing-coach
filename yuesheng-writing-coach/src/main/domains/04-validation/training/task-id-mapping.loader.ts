/**
 * Task ID Mapping Loader
 *
 * 提供训练任务三向 ID 映射的查询 API：
 * - T0XX ↔ TRAIN-PXXX 双向查询
 * - TRAIN-PXXX ↔ CH-PXXX 双向查询
 * - PRAC-XXX 关联症候查询
 * - 孤儿项追踪
 *
 * 单一真相源：resources/config/task-id-mapping.json
 */

import * as fs from 'fs';
import * as path from 'path';

import type { TaskIdMappingJson } from './task-id-mapping.types';

// ==============================
// 常量：JSON 文件路径
// ==============================

const MAPPING_JSON_PATH = path.resolve(
  __dirname,
  '..',
  '..',
  '..',
  '..',
  '..',
  'resources',
  'config',
  'task-id-mapping.json',
);

let cached: TaskIdMappingJson | null = null;

/** 加载映射（带缓存） */
function load(): TaskIdMappingJson {
  if (cached) return cached;
  const raw = fs.readFileSync(MAPPING_JSON_PATH, 'utf-8');
  cached = JSON.parse(raw) as TaskIdMappingJson;
  return cached;
}

/** 强制重载（测试用） */
export function reload(): void {
  cached = null;
}

/** 是否已加载 */
export function isLoaded(): boolean {
  return cached !== null;
}

// ==============================
// 双向查询 API
// ==============================

/** T0XX → TRAIN-PXXX（返回 TRAIN ID 或 null，TBD 返回 null） */
export function t0xxToTrain(t0xxId: string): string | null {
  const data = load();
  const entry = data.T0XX_to_TRAIN[t0xxId];
  if (!entry) return null;
  return entry.mapsTo === 'TBD' ? null : entry.mapsTo;
}

/** T0XX → 映射详情（含 rationale） */
export function t0xxToTrainDetail(t0xxId: string): {
  mapsTo: string | null;
  rationale: string;
  isTBD: boolean;
} | null {
  const data = load();
  const entry = data.T0XX_to_TRAIN[t0xxId];
  if (!entry) return null;
  return {
    mapsTo: entry.mapsTo === 'TBD' ? null : entry.mapsTo,
    rationale: entry.rationale,
    isTBD: entry.mapsTo === 'TBD',
  };
}

/** TRAIN-PXXX → T0XX（一对一） */
export function trainToT0xx(trainId: string): string | null {
  const data = load();
  return data.TRAIN_to_T0XX[trainId] ?? null;
}

/** TRAIN-PXXX → CH-PXXX 列表 */
export function trainToChallenges(trainId: string): string[] {
  const data = load();
  const entry = data.TRAIN_to_CH[trainId];
  if (!entry) return [];
  return entry.relatedChallenges;
}

/** CH-PXXX → TRAIN-PXXX 列表（多对一） */
export function challengeToTrains(chId: string): string[] {
  const data = load();
  return data.CH_to_TRAIN[chId] ?? [];
}

/** 症候级映射总览 */
export function getSyndromeMapping(syndromeId: string): {
  T0XX: string[];
  TRAIN_PXXX: string[];
  CH_PXXX: string[];
  note?: string;
} | null {
  const data = load();
  const entry = data.syndromeMapping[syndromeId];
  if (!entry) return null;
  return {
    T0XX: entry.T0XX,
    TRAIN_PXXX: entry.TRAIN_PXXX,
    CH_PXXX: entry.CH_PXXX,
    note: entry._note,
  };
}

/** PRAC-XXX 关联症候 */
export function pracToSyndrome(pracId: string): string | null {
  const data = load();
  const entry = data.PRAC_to_syndrome[pracId];
  return entry ? entry.primarySyndrome : null;
}

// ==============================
// 孤儿项查询
// ==============================

/** 孤儿 T0XX（无对应 TRAIN-PXXX） */
export function getOrphanT0XX(): Array<{ id: string; reason: string; action?: string }> {
  return load().orphanTracking.orphanT0XX;
}

/** 孤儿 TRAIN-PXXX（无对应 T0XX） */
export function getOrphanTRAIN(): Array<{ id: string; reason: string }> {
  return load().orphanTracking.orphanTRAIN;
}

/** 孤儿 CH-PXXX（无对应 TRAIN-PXXX） */
export function getOrphanChallenges(): Array<{ id: string; reason: string }> {
  return load().orphanTracking.orphanCH;
}

/** 孤儿症候（仅在某一体系存在） */
export function getOrphanSyndromes(): Array<{
  id: string;
  name: string;
  presentIn: { T0XX: boolean; TRAIN_PXXX: boolean; CH_PXXX: boolean };
  action: string;
}> {
  return load().orphanTracking.orphanSyndromes;
}

// ==============================
// 完整性校验（消费方去重逻辑）
// ==============================

/**
 * 校验三向映射的完整性
 * 返回 { isComplete, issues: string[] }
 */
export function validateMappingIntegrity(): {
  isComplete: boolean;
  issues: string[];
} {
  const data = load();
  const issues: string[] = [];

  // 1. 检查所有 T0XX 是否都有 TRAIN 映射（允许 TBD）
  for (const t0xxId of Object.keys(data.T0XX_to_TRAIN)) {
    if (t0xxId === '_comment') continue;
    const entry = data.T0XX_to_TRAIN[t0xxId];
    if (!entry) {
      issues.push(`T0XX ${t0xxId} 缺少映射规则`);
    }
  }

  // 2. 检查所有 TRAIN-PXXX 是否有 CH 映射（PRAC-XXX 除外）
  for (const trainId of Object.keys(data.TRAIN_to_CH)) {
    if (trainId === '_comment') continue;
    const entry = data.TRAIN_to_CH[trainId];
    if (!entry || !entry.relatedChallenges || entry.relatedChallenges.length === 0) {
      issues.push(`TRAIN ${trainId} 缺少 CH 映射或相关挑战列表为空`);
    }
  }

  // 3. 检查 TRAIN_to_CH 的挑战 ID 是否都存在
  const allChIds = new Set(Object.keys(data.CH_to_TRAIN).filter(k => k !== '_comment'));
  for (const trainId of Object.keys(data.TRAIN_to_CH)) {
    const chList = data.TRAIN_to_CH[trainId]?.relatedChallenges || [];
    for (const chId of chList) {
      if (!allChIds.has(chId)) {
        issues.push(`TRAIN ${trainId} 引用了不存在的 CH ${chId}`);
      }
    }
  }

  // 4. 检查 CH_to_TRAIN 的反向引用完整性：非空列表必须指向存在的 TRAIN
  const allTrainIds = new Set(Object.keys(data.TRAIN_to_T0XX).filter(k => k !== '_comment'));
  for (const [chId, trainList] of Object.entries(data.CH_to_TRAIN)) {
    if (chId === '_comment') continue;
    for (const trainId of trainList) {
      if (!allTrainIds.has(trainId)) {
        issues.push(`CH ${chId} 引用了不存在的 TRAIN ${trainId}`);
      }
    }
  }

  return {
    isComplete: issues.length === 0,
    issues,
  };
}

/** 统计信息 */
export function getStatistics(): {
  T0XX: number;
  TRAIN_PXXX: number;
  TRAIN_PXXX_general: number;
  CH_PXXX: number;
  syndromesCovered: number;
  orphanSyndromes: number;
  orphanT0XX: number;
  orphanTRAIN: number;
  orphanCH: number;
} {
  return load().statistics;
}
