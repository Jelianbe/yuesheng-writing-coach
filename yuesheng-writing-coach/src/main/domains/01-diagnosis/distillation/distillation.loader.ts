/**
 * 蒸馏素材 Loader
 *
 * 职责：读取 resources/distillation-index.json，提供类型化查询接口，
 * 供 DiagnosisService、TeachingStrategyRouter、TrainingRecommendationService 使用。
 *
 * 设计原则：
 * - 惰性加载：首次使用时读取 JSON，加载后缓存
 * - 类型安全：所有返回数据通过 TypeScript 接口约束
 * - 无外部依赖：Loader 独立，不引入循环依赖
 *
 * 依据：dev-docs/designs/sprint-15-plan.md §T15-A
 */

import * as fs from 'fs';
import * as path from 'path';

import type {
  DistillationIndexJson,
  DistillationEntry,
  DistillationSearchOptions,
  DistillationStatistics,
} from './distillation.types';

// ==============================
// 常量：JSON 文件路径
// ==============================

const INDEX_JSON_PATH = path.resolve(
  __dirname,
  '../../../../../resources/distillation-index.json',
);

// ==============================
// 内部状态
// ==============================

let indexData: DistillationIndexJson | null = null;
let loaded = false;

// ==============================
// 缓存查询结果
// ==============================

let cachedById: Map<string, DistillationEntry> | null = null;
let cachedByLegacyId: Map<string, DistillationEntry> | null = null;
let cachedByBatch: Map<string, DistillationEntry[]> | null = null;

// ==============================
// 内部方法
// ==============================

function loadJson<T>(filePath: string, label: string): T {
  try {
    const raw = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(raw) as T;
  } catch (err) {
    console.warn(`[DistillationLoader] Failed to load ${label} at ${filePath}:`, err);
    return {} as T;
  }
}

function ensureLoaded(): void {
  if (loaded) return;

  indexData = loadJson<DistillationIndexJson>(INDEX_JSON_PATH, 'distillation-index.json');

  // 空值保护：如果文件缺失或格式错误，返回空索引
  if (!indexData || !Array.isArray(indexData.entries)) {
    console.warn('[DistillationLoader] distillation-index.json is empty or invalid');
    indexData = {
      version: '0.0.0',
      generatedAt: '',
      description: '',
      sources: { batch001: '', batch002: '', batch003: '', tags: '' },
      statistics: {
        total: 0, batch001: 0, batch002: 0, batch003: 0,
        taggedByHuman: 0, taggedByHeuristic: 0,
      },
      entries: [],
    };
  }

  loaded = true;
  buildCaches();
}

function buildCaches(): void {
  const entries = indexData!.entries;

  // 按 ID 索引
  cachedById = new Map(entries.map(e => [e.id, e]));

  // 按 legacyId 索引
  cachedByLegacyId = new Map(entries.map(e => [e.legacyId, e]));

  // 按批次索引
  const byBatch = new Map<string, DistillationEntry[]>();
  for (const e of entries) {
    const list = byBatch.get(e.batch) ?? [];
    list.push(e);
    byBatch.set(e.batch, list);
  }
  cachedByBatch = byBatch;
}

/** 检查条目是否匹配症候（主或次） */
function matchSyndrome(entry: DistillationEntry, syndromeId: string): boolean {
  if (entry.syndromes.primary === syndromeId) return true;
  if (entry.syndromes.secondary.includes(syndromeId)) return true;
  return false;
}

/** 关键词搜索（content + summary + teachingAction） */
function matchQuery(entry: DistillationEntry, query: string): boolean {
  const q = query.toLowerCase();
  return (
    entry.content.toLowerCase().includes(q) ||
    entry.summary.toLowerCase().includes(q) ||
    (entry.teachingAction?.toLowerCase().includes(q) ?? false)
  );
}

// ==============================
// 公开 API
// ==============================

/** 按新格式 ID 查询 */
export function getById(id: string): DistillationEntry | null {
  ensureLoaded();
  return cachedById!.get(id) ?? null;
}

/** 按旧格式 ID 查询（B-001 / J-001 / K-001 / X-001 / PL-01 / SC-01 / DG-01） */
export function getByLegacyId(legacyId: string): DistillationEntry | null {
  ensureLoaded();
  return cachedByLegacyId!.get(legacyId) ?? null;
}

/** 按症候 ID 查询（匹配 primary + secondary） */
export function getBySyndrome(syndromeId: string): DistillationEntry[] {
  ensureLoaded();
  return indexData!.entries.filter(e => matchSyndrome(e, syndromeId));
}

/** 按批次查询 */
export function getByBatch(batch: '001' | '002' | '003'): DistillationEntry[] {
  ensureLoaded();
  return [...(cachedByBatch!.get(batch) ?? [])];
}

/** 按标注方式查询 */
export function getByTag(taggedBy: 'human' | 'heuristic'): DistillationEntry[] {
  ensureLoaded();
  return indexData!.entries.filter(e => e.taggedBy === taggedBy);
}

/** 多条件搜索 */
export function search(options: DistillationSearchOptions): DistillationEntry[] {
  ensureLoaded();
  let results = indexData!.entries;

  if (options.query) {
    results = results.filter(e => matchQuery(e, options.query!));
  }
  if (options.syndromeId) {
    results = results.filter(e => matchSyndrome(e, options.syndromeId!));
  }
  if (options.batch) {
    results = results.filter(e => e.batch === options.batch);
  }
  if (options.taggedBy) {
    results = results.filter(e => e.taggedBy === options.taggedBy);
  }
  if (options.limit && options.limit > 0) {
    results = results.slice(0, options.limit);
  }

  return results;
}

/** 全文搜索（关键词） */
export function searchByKeyword(keyword: string, limit?: number): DistillationEntry[] {
  return search({ query: keyword, limit });
}

/** 获取所有素材 */
export function getAll(): DistillationEntry[] {
  ensureLoaded();
  return [...indexData!.entries];
}

/** 随机抽样（用于教学推荐的多样性） */
export function getRandom(n: number): DistillationEntry[] {
  ensureLoaded();
  const all = indexData!.entries;
  if (n >= all.length) return [...all];

  // Fisher-Yates 部分洗牌（前 n 个）
  const arr = [...all];
  for (let i = 0; i < n; i++) {
    const j = i + Math.floor(Math.random() * (arr.length - i));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr.slice(0, n);
}

/** 获取统计信息 */
export function getStatistics(): DistillationStatistics {
  ensureLoaded();
  const entries = indexData!.entries;
  const stats: DistillationStatistics = {
    total: entries.length,
    byBatch: {},
    byTag: {},
    bySyndromePrimary: {},
  };

  for (const e of entries) {
    stats.byBatch[e.batch] = (stats.byBatch[e.batch] ?? 0) + 1;
    stats.byTag[e.taggedBy] = (stats.byTag[e.taggedBy] ?? 0) + 1;
    if (e.syndromes.primary) {
      stats.bySyndromePrimary[e.syndromes.primary] =
        (stats.bySyndromePrimary[e.syndromes.primary] ?? 0) + 1;
    }
  }

  return stats;
}

/** 重新加载（外部文件变动时） */
export function reload(): void {
  loaded = false;
  indexData = null;
  cachedById = null;
  cachedByLegacyId = null;
  cachedByBatch = null;
  ensureLoaded();
}

/** 检查 Loader 是否已就绪 */
export function isLoaded(): boolean {
  return loaded;
}
