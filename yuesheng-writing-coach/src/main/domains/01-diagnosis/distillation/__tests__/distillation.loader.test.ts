/**
 * 蒸馏素材 Loader 单元测试
 *
 * Sprint 15 T15-A 覆盖：
 * - getById / getByLegacyId 查询
 * - getBySyndrome（primary + secondary 匹配）
 * - getByBatch / getByTag
 * - search 多条件
 * - searchByKeyword
 * - getAll / getRandom
 * - getStatistics
 * - reload / isLoaded
 * - 461 条数据完整性校验
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  getById,
  getByLegacyId,
  getBySyndrome,
  getByBatch,
  getByTag,
  search,
  searchByKeyword,
  getAll,
  getRandom,
  getStatistics,
  reload,
  isLoaded,
} from '../distillation.loader';

beforeEach(() => {
  reload();
});

describe('Loader 初始化', () => {
  it('首次调用后 isLoaded 应为 true', () => {
    expect(isLoaded()).toBe(true);
  });

  it('reload 后重新加载', () => {
    reload();
    expect(isLoaded()).toBe(true);
  });

  it('getAll 应返回 461 条素材', () => {
    const all = getAll();
    expect(all).toHaveLength(461);
  });
});

describe('getById — 新格式 ID 查询', () => {
  it('DST-001-001 应返回 B-001（避雷第 1 条）', () => {
    const entry = getById('DST-001-001');
    expect(entry).not.toBeNull();
    expect(entry?.legacyId).toBe('B-001');
    expect(entry?.batch).toBe('001');
    expect(entry?.batchLabel).toBe('避雷100条');
  });

  it('DST-001-200 应返回 J-100（教学第 100 条）', () => {
    const entry = getById('DST-001-200');
    expect(entry).not.toBeNull();
    expect(entry?.legacyId).toBe('J-100');
    expect(entry?.batchLabel).toBe('教学指导100条');
  });

  it('DST-002-100 应返回 K-100（困境第 100 条）', () => {
    const entry = getById('DST-002-100');
    expect(entry).not.toBeNull();
    expect(entry?.legacyId).toBe('K-100');
    expect(entry?.batchLabel).toBe('实战困境100条');
  });

  it('DST-002-200 应返回 X-100（习惯第 100 条）', () => {
    const entry = getById('DST-002-200');
    expect(entry).not.toBeNull();
    expect(entry?.legacyId).toBe('X-100');
    expect(entry?.batchLabel).toBe('习惯养成100条');
  });

  it('DST-003-001 应返回 PL-01（情节第 1 条）', () => {
    const entry = getById('DST-003-001');
    expect(entry).not.toBeNull();
    expect(entry?.legacyId).toBe('PL-01');
    expect(entry?.batchLabel).toBe('情节薄弱25条');
  });

  it('DST-003-061 应返回 DG-18（对话第 18 条）', () => {
    const entry = getById('DST-003-061');
    expect(entry).not.toBeNull();
    expect(entry?.legacyId).toBe('DG-18');
  });

  it('未知 ID 应返回 null', () => {
    expect(getById('DST-999-999')).toBeNull();
    expect(getById('INVALID')).toBeNull();
  });
});

describe('getByLegacyId — 旧格式 ID 查询', () => {
  it('B-001 应返回 DST-001-001', () => {
    const entry = getByLegacyId('B-001');
    expect(entry?.id).toBe('DST-001-001');
  });

  it('J-100 应返回 DST-001-200', () => {
    const entry = getByLegacyId('J-100');
    expect(entry?.id).toBe('DST-001-200');
  });

  it('K-100 应返回 DST-002-100', () => {
    const entry = getByLegacyId('K-100');
    expect(entry?.id).toBe('DST-002-100');
  });

  it('X-100 应返回 DST-002-200', () => {
    const entry = getByLegacyId('X-100');
    expect(entry?.id).toBe('DST-002-200');
  });

  it('PL-25 / SC-18 / DG-18 应正确定位', () => {
    expect(getByLegacyId('PL-25')?.id).toBe('DST-003-025');
    expect(getByLegacyId('SC-18')?.id).toBe('DST-003-043');
    expect(getByLegacyId('DG-18')?.id).toBe('DST-003-061');
  });

  it('未知 legacyId 应返回 null', () => {
    expect(getByLegacyId('Z-999')).toBeNull();
  });
});

describe('getByBatch — 批次查询', () => {
  it('批次 001 应返回 200 条', () => {
    const entries = getByBatch('001');
    expect(entries).toHaveLength(200);
    expect(entries.every(e => e.batch === '001')).toBe(true);
  });

  it('批次 002 应返回 200 条', () => {
    const entries = getByBatch('002');
    expect(entries).toHaveLength(200);
    expect(entries.every(e => e.batch === '002')).toBe(true);
  });

  it('批次 003 应返回 61 条', () => {
    const entries = getByBatch('003');
    expect(entries).toHaveLength(61);
    expect(entries.every(e => e.batch === '003')).toBe(true);
  });
});

describe('getByTag — 标注方式查询', () => {
  it('人工标注（human）应返回 400 条', () => {
    const entries = getByTag('human');
    expect(entries).toHaveLength(400);
    expect(entries.every(e => e.taggedBy === 'human')).toBe(true);
  });

  it('启发式标注（heuristic）应返回 61 条（批次 003 待 LLM 标注）', () => {
    const entries = getByTag('heuristic');
    expect(entries).toHaveLength(61);
    expect(entries.every(e => e.taggedBy === 'heuristic')).toBe(true);
  });
});

describe('getBySyndrome — 症候查询', () => {
  it('P001 应有匹配的素材', () => {
    const entries = getBySyndrome('P001');
    expect(entries.length).toBeGreaterThan(0);
    expect(entries.every(e =>
      e.syndromes.primary === 'P001' || e.syndromes.secondary.includes('P001')
    )).toBe(true);
  });

  it('P003 应匹配（情绪标签化）', () => {
    const entries = getBySyndrome('P003');
    expect(entries.length).toBeGreaterThan(0);
    expect(entries.every(e =>
      e.syndromes.primary === 'P003' || e.syndromes.secondary.includes('P003')
    )).toBe(true);
  });

  it('P006 应匹配（节奏停滞）', () => {
    const entries = getBySyndrome('P006');
    expect(entries.length).toBeGreaterThan(0);
    expect(entries.every(e =>
      e.syndromes.primary === 'P006' || e.syndromes.secondary.includes('P006')
    )).toBe(true);
  });

  it('未知症候应返回空数组', () => {
    expect(getBySyndrome('P999')).toEqual([]);
  });
});

describe('search — 多条件搜索', () => {
  it('按 query 搜索关键词', () => {
    const results = search({ query: '节奏' });
    expect(results.length).toBeGreaterThan(0);
    expect(results.every(e =>
      e.content.includes('节奏') || e.summary.includes('节奏') || (e.teachingAction?.includes('节奏') ?? false)
    )).toBe(true);
  });

  it('按 syndromeId 过滤', () => {
    const results = search({ syndromeId: 'P001' });
    expect(results.length).toBeGreaterThan(0);
    expect(results.every(e =>
      e.syndromes.primary === 'P001' || e.syndromes.secondary.includes('P001')
    )).toBe(true);
  });

  it('按 batch 过滤', () => {
    const results = search({ batch: '003' });
    expect(results).toHaveLength(61);
  });

  it('按 taggedBy 过滤', () => {
    const results = search({ taggedBy: 'human' });
    expect(results).toHaveLength(400);
  });

  it('组合条件 batch + taggedBy', () => {
    const results = search({ batch: '003', taggedBy: 'heuristic' });
    expect(results).toHaveLength(61);
  });

  it('limit 限制返回条数', () => {
    const results = search({ limit: 5 });
    expect(results).toHaveLength(5);
  });
});

describe('searchByKeyword — 关键词搜索', () => {
  it('搜索"世界观"应返回相关素材', () => {
    const results = searchByKeyword('世界观');
    expect(results.length).toBeGreaterThan(0);
  });

  it('搜索不存在的关键词应返回空数组', () => {
    const results = searchByKeyword('XXXXX-NONEXISTENT-XXXXX');
    expect(results).toEqual([]);
  });

  it('limit 限制生效', () => {
    const results = searchByKeyword('的', 3);
    expect(results).toHaveLength(3);
  });
});

describe('getRandom — 随机抽样', () => {
  it('抽样 10 条应返回 10 条', () => {
    const results = getRandom(10);
    expect(results).toHaveLength(10);
  });

  it('抽样超过总数应返回全部', () => {
    const results = getRandom(1000);
    expect(results).toHaveLength(461);
  });

  it('抽样 0 条应返回空数组', () => {
    const results = getRandom(0);
    expect(results).toEqual([]);
  });
});

describe('getStatistics — 统计信息', () => {
  it('总数应为 461', () => {
    const stats = getStatistics();
    expect(stats.total).toBe(461);
  });

  it('按批次统计：001=200, 002=200, 003=61', () => {
    const stats = getStatistics();
    expect(stats.byBatch['001']).toBe(200);
    expect(stats.byBatch['002']).toBe(200);
    expect(stats.byBatch['003']).toBe(61);
  });

  it('按标签统计：human=400, heuristic=61', () => {
    const stats = getStatistics();
    expect(stats.byTag['human']).toBe(400);
    expect(stats.byTag['heuristic']).toBe(61);
  });

  it('按主症候统计应包含 P001~P012', () => {
    const stats = getStatistics();
    expect(stats.bySyndromePrimary['P001']).toBeGreaterThan(0);
    expect(stats.bySyndromePrimary['P003']).toBeGreaterThan(0);
    expect(stats.bySyndromePrimary['P006']).toBeGreaterThan(0);
  });
});

describe('数据完整性校验', () => {
  it('所有条目 ID 必须符合 DST-XXX-NNN 格式', () => {
    const all = getAll();
    expect(all.every(e => /^DST-\d{3}-\d{3}$/.test(e.id))).toBe(true);
  });

  it('所有条目必须有非空 summary 和 content', () => {
    const all = getAll();
    expect(all.every(e => e.summary.length > 0 && e.content.length > 0)).toBe(true);
  });

  it('批次 003 全部为 heuristic 标注（待 LLM 标注）', () => {
    const batch003 = getByBatch('003');
    expect(batch003.every(e => e.taggedBy === 'heuristic')).toBe(true);
  });

  it('批次 001+002 全部为 human 标注（D03 索引合并）', () => {
    const batch001 = getByBatch('001');
    const batch002 = getByBatch('002');
    expect(batch001.every(e => e.taggedBy === 'human')).toBe(true);
    expect(batch002.every(e => e.taggedBy === 'human')).toBe(true);
  });
});
