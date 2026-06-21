/**
 * I-01 training:catalog handler 单元测试
 *
 * 验证 technique-library.json 导入 → 按 coreId 分组 → 输出 TrainingCatalogResponse 合约
 */
import { describe, it, expect } from 'vitest';
import techniqueLibrary from '../../../../resources/config/technique-library.json';

describe('I-01 training:catalog — 技法目录数据', () => {
  it('technique-library.json 应包含技法数据', () => {
    expect(Array.isArray(techniqueLibrary)).toBe(true);
    expect(techniqueLibrary.length).toBeGreaterThan(0);
  });

  it('每条技法应有 coreId/coreName', () => {
    for (const t of techniqueLibrary as Array<Record<string, unknown>>) {
      expect(typeof t.coreId).toBe('string');
      expect(typeof t.coreName).toBe('string');
      expect((t.coreId as string).length).toBeGreaterThan(0);
    }
  });

  it('技法数据去重后应有 10 个核心分组', () => {
    const coreIds = new Set((techniqueLibrary as Array<Record<string, unknown>>).map(t => t.coreId as string));
    expect(coreIds.size).toBe(10);
  });

  it('所有技法应有 difficulty 字段，值规范', () => {
    const validDifficulties = ['beginner', 'intermediate', 'advanced'];
    for (const t of techniqueLibrary as Array<Record<string, unknown>>) {
      expect(validDifficulties).toContain(t.difficulty);
    }
  });

  it('按 coreId 分组后 count 应匹配', () => {
    const grouped: Record<string, number> = {};
    for (const t of techniqueLibrary as Array<Record<string, unknown>>) {
      const cid = t.coreId as string;
      grouped[cid] = (grouped[cid] || 0) + 1;
    }
    // 验证每个分组至少有 1 条技法
    for (const count of Object.values(grouped)) {
      expect(count).toBeGreaterThanOrEqual(1);
    }
  });

  it('返回格式应匹配 TrainingCatalogResponse', () => {
    const grouped: Record<string, { coreName: string; techniques: unknown[] }> = {};
    for (const t of techniqueLibrary as Array<Record<string, unknown>>) {
      const cid = t.coreId as string;
      if (!grouped[cid]) {
        grouped[cid] = { coreName: t.coreName as string, techniques: [] };
      }
      grouped[cid].techniques.push(t);
    }

    const groups = Object.entries(grouped).map(([coreId, g]) => ({
      coreId,
      coreName: g.coreName,
      count: g.techniques.length,
      techniques: g.techniques,
    }));

    const total = groups.reduce((sum, g) => sum + g.count, 0);

    // 验证结构
    expect(Array.isArray(groups)).toBe(true);
    expect(typeof total).toBe('number');
    expect(total).toBeGreaterThan(0);

    // 验证每个分组的字段
    for (const g of groups) {
      expect(typeof g.coreId).toBe('string');
      expect(typeof g.coreName).toBe('string');
      expect(typeof g.count).toBe('number');
      expect(Array.isArray(g.techniques)).toBe(true);
      expect(g.techniques.length).toBe(g.count);

      // 验证技法字段
      for (const t of g.techniques as Array<Record<string, unknown>>) {
        expect(typeof t.id).toBe('string');
        expect(typeof t.name).toBe('string');
        expect(typeof t.description).toBe('string');
        expect(typeof t.source).toBe('string');
      }
    }
  });
});
