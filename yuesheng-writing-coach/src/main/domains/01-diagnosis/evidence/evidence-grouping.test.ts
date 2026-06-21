/**
 * 证据分组工具测试
 *
 * 验证：
 * 1. 按 syndromeRef 正确分组 keyPassages
 * 2. 无 syndromeRef 时降级为共享模式
 * 3. 每症候最多 2 条证据
 * 4. 证据去重
 * 5. syndromeRef 有效性校验
 * 6. 症候无对应证据时返回空数组（不返回 fallback）
 */

import { describe, it, expect, vi } from 'vitest';
import { groupPassagesBySyndrome, getEvidenceForSyndrome } from './evidence-grouping';
import type { KeyPassage } from '../../../../shared/types/index';

// === 测试数据构造 ===

function makePassage(text: string, issue: string, syndromeRef?: string): KeyPassage {
  return { text, issue, syndromeRef };
}

// === groupPassagesBySyndrome 测试 ===

describe('groupPassagesBySyndrome', () => {
  it('should group passages by syndromeRef', () => {
    const passages: KeyPassage[] = [
      makePassage('段落A', '世界观太宏大', 'P001'),
      makePassage('段落B', '设定堆砌', 'P001'),
      makePassage('段落C', '情绪标签化', 'P003'),
      makePassage('段落D', '角色无动机', 'P002'),
    ];

    const result = groupPassagesBySyndrome(passages);

    // 每症候最多 2 条
    expect(result.get('P001')).toEqual(['段落A', '段落B']);
    expect(result.get('P003')).toEqual(['段落C']);
    expect(result.get('P002')).toEqual(['段落D']);
    expect(result.has('__shared__')).toBe(false);
  });

  it('should fallback to shared mode when no syndromeRef present', () => {
    const passages: KeyPassage[] = [
      makePassage('段落A', '问题A'),
      makePassage('段落B', '问题B'),
      makePassage('段落C', '问题C'),
      makePassage('段落D', '问题D'),
    ];

    const result = groupPassagesBySyndrome(passages);

    expect(result.has('__shared__')).toBe(true);
    expect(result.get('__shared__')).toEqual(['段落A', '段落B', '段落C']);
  });

  it('should discard passages without syndromeRef in group mode', () => {
    const passages: KeyPassage[] = [
      makePassage('段落A', '世界观', 'P001'),
      makePassage('段落B', '情绪', 'P003'),
      makePassage('段落C', '无标注'), // 无 syndromeRef
      makePassage('段落D', '世界观2', 'P001'),
    ];

    const result = groupPassagesBySyndrome(passages);

    // 有 syndromeRef 的会被分组
    expect(result.get('P001')).toEqual(['段落A', '段落D']);
    expect(result.get('P003')).toEqual(['段落B']);
    // 无 syndromeRef 的不影响分组结果
    expect(result.has('__shared__')).toBe(false);
    // 未标注的"段落C"被丢弃，不在任何分组中
    expect(result.get('P001')).not.toContain('段落C');
  });

  it('should handle empty passages', () => {
    const passages: KeyPassage[] = [];
    const result = groupPassagesBySyndrome(passages);

    expect(result.has('__shared__')).toBe(true);
    expect(result.get('__shared__')).toEqual([]);
  });

  it('should limit shared passages to 3', () => {
    const passages: KeyPassage[] = [
      makePassage('1', 'a'),
      makePassage('2', 'b'),
      makePassage('3', 'c'),
      makePassage('4', 'd'),
      makePassage('5', 'e'),
    ];

    const result = groupPassagesBySyndrome(passages);

    expect(result.get('__shared__')).toHaveLength(3);
    expect(result.get('__shared__')).toEqual(['1', '2', '3']);
  });

  it('should limit each syndrome to 2 passages', () => {
    const passages: KeyPassage[] = [
      makePassage('1', 'a', 'P001'),
      makePassage('2', 'b', 'P001'),
      makePassage('3', 'c', 'P001'), // 第 3 条，应该被截断
      makePassage('4', 'd', 'P002'),
    ];

    const result = groupPassagesBySyndrome(passages);

    expect(result.get('P001')).toHaveLength(2);
    expect(result.get('P001')).toEqual(['1', '2']);
    expect(result.get('P002')).toEqual(['4']);
  });

  it('should deduplicate evidence within same syndrome', () => {
    const passages: KeyPassage[] = [
      makePassage('同一段落', '问题A', 'P001'),
      makePassage('同一段落', '问题A', 'P001'), // 重复
      makePassage('另一段落', '问题B', 'P001'),
    ];

    const result = groupPassagesBySyndrome(passages);

    expect(result.get('P001')).toHaveLength(2);
    expect(result.get('P001')).toEqual(['同一段落', '另一段落']);
  });

  it('should reject invalid syndromeRef format', () => {
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    const passages: KeyPassage[] = [
      makePassage('正常段落', '问题A', 'P001'),
      makePassage('拼写错误', '问题B', 'P00l'), // 小写 L 代替 1
      makePassage('格式错误', '问题C', 'P01'), // 少一位
      makePassage('格式错误2', '问题D', 'P0001'), // 多一位
    ];

    const result = groupPassagesBySyndrome(passages);

    expect(result.get('P001')).toEqual(['正常段落']);
    expect(result.has('P00l')).toBe(false);
    expect(result.has('P01')).toBe(false);
    expect(result.has('P0001')).toBe(false);
    expect(warnSpy).toHaveBeenCalledTimes(3);

    warnSpy.mockRestore();
  });
});

// === getEvidenceForSyndrome 测试 ===

describe('getEvidenceForSyndrome', () => {
  it('should return grouped passages for a syndrome', () => {
    const grouped = new Map<string, string[]>();
    grouped.set('P001', ['段落A', '段落B']);
    grouped.set('P003', ['段落C']);

    const evidence = getEvidenceForSyndrome(grouped, 'P001', []);

    expect(evidence).toEqual(['段落A', '段落B']);
  });

  it('should return fallback when syndrome has no passages', () => {
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    const grouped = new Map<string, string[]>();
    grouped.set('P001', ['段落A']);
    const fallback = ['fallback1', 'fallback2'];

    const evidence = getEvidenceForSyndrome(grouped, 'P099', fallback);

    expect(evidence).toEqual([]);
    expect(warnSpy).toHaveBeenCalledTimes(1);

    warnSpy.mockRestore();
  });

  it('should return shared passages in fallback mode', () => {
    const grouped = new Map<string, string[]>();
    grouped.set('__shared__', ['共享1', '共享2']);

    const evidence = getEvidenceForSyndrome(grouped, 'P001', []);

    expect(evidence).toEqual(['共享1', '共享2']);
  });

  it('should return empty for unknown syndrome with empty fallback', () => {
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    const grouped = new Map<string, string[]>();
    grouped.set('P001', ['段落A']);

    const evidence = getEvidenceForSyndrome(grouped, 'P099', []);

    expect(evidence).toEqual([]);
    expect(warnSpy).toHaveBeenCalledTimes(1);

    warnSpy.mockRestore();
  });
});

// === 集成场景测试 ===

describe('集成场景：分组 + 获取', () => {
  it('完整流程：AI 输出带 syndromeRef → 分组 → 各症候取证据', () => {
    const passages: KeyPassage[] = [
      makePassage('整个大陆被分为五个王国，每个王国都有独特的魔法体系', '世界观膨胀', 'P001'),
      makePassage('他很紧张，心里充满了不安和恐惧', '情绪标签化', 'P003'),
      makePassage('魔法体系包含元素、暗影、生命三个分支', '设定堆砌', 'P001'),
    ];

    const grouped = groupPassagesBySyndrome(passages);

    // P001 应该有 2 条证据
    const p001Evidence = getEvidenceForSyndrome(grouped, 'P001', []);
    expect(p001Evidence).toHaveLength(2);
    expect(p001Evidence[0]).toContain('大陆');
    expect(p001Evidence[1]).toContain('魔法体系');

    // P003 应该有 1 条证据
    const p003Evidence = getEvidenceForSyndrome(grouped, 'P003', []);
    expect(p003Evidence).toHaveLength(1);
    expect(p003Evidence[0]).toContain('紧张');
  });

  it('降级场景：AI 未输出 syndromeRef → 所有症候共享', () => {
    const passages: KeyPassage[] = [
      makePassage('段落A', '问题A'),
      makePassage('段落B', '问题B'),
      makePassage('段落C', '问题C'),
    ];

    const grouped = groupPassagesBySyndrome(passages);

    // 所有症候都用共享证据
    const p001Evidence = getEvidenceForSyndrome(grouped, 'P001', []);
    const p003Evidence = getEvidenceForSyndrome(grouped, 'P003', []);

    expect(p001Evidence).toEqual(['段落A', '段落B', '段落C']);
    expect(p003Evidence).toEqual(['段落A', '段落B', '段落C']);
  });

  it('症候无对应证据 → 空数组（不返回 fallback）', () => {
    const passages: KeyPassage[] = [
      makePassage('段落A', '世界观', 'P001'),
      makePassage('段落B', '情绪', 'P003'),
    ];

    const grouped = groupPassagesBySyndrome(passages);
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    // P002 没有对应的 keyPassage
    const p002Evidence = getEvidenceForSyndrome(grouped, 'P002', ['fallback']);

    expect(p002Evidence).toEqual([]);
    expect(warnSpy).toHaveBeenCalledTimes(1);

    warnSpy.mockRestore();
  });
});
