/**
 * diagnosis-translations 单元测试
 * 覆盖：翻译函数、批量翻译、未知症候降级
 */

import { describe, it, expect } from 'vitest';
import { diagnosisToUserFacing, syndromesToUserFacing } from '../diagnosis-translations';

describe('diagnosisToUserFacing', () => {
  it('P001 L1 → 正面名称 + L1 描述 + mild', () => {
    const result = diagnosisToUserFacing('P001', 'L1');
    expect(result.name).toBe('你的故事设定很丰富');
    expect(result.description).toBe('开场可以试着先展示主角的日常');
    expect(result.severityLevel).toBe('mild');
  });

  it('P001 L2 → 正面名称 + L2 描述 + moderate', () => {
    const result = diagnosisToUserFacing('P001', 'L2');
    expect(result.name).toBe('你的故事设定很丰富');
    expect(result.description).toBe('但主角的出场还不太清晰');
    expect(result.severityLevel).toBe('moderate');
  });

  it('P002 L3 → 正面名称 + L3 描述 + severe', () => {
    const result = diagnosisToUserFacing('P002', 'L3');
    expect(result.name).toBe('角色互动自然');
    expect(result.description).toBe('角色像工具人，需要赋予独立动机');
    expect(result.severityLevel).toBe('severe');
  });

  it('P006 L2 → L2 描述', () => {
    const result = diagnosisToUserFacing('P006', 'L2');
    expect(result.name).toBe('故事框架完整');
    expect(result.description).toBe('让主角在前三段做个选择来推动故事');
    expect(result.severityLevel).toBe('moderate');
  });

  it('P006 L3 → L3 描述', () => {
    const result = diagnosisToUserFacing('P006', 'L3');
    expect(result.name).toBe('故事框架完整');
    expect(result.description).toBe('故事缺乏推动力，建议制造一个主动选择');
    expect(result.severityLevel).toBe('severe');
  });

  it('未知症候 → 返回症候 ID + 空描述', () => {
    const result = diagnosisToUserFacing('P999', 'L2');
    expect(result.name).toBe('P999');
    expect(result.description).toBe('');
    expect(result.severityLevel).toBe('moderate');
  });
});

describe('syndromesToUserFacing', () => {
  it('批量翻译', () => {
    const input = [
      { id: 'P001', name: '世界观膨胀', severity: 'L1' as const },
      { id: 'P003', name: '情绪标签化', severity: 'L2' as const },
    ];
    const result = syndromesToUserFacing(input);
    expect(result).toHaveLength(2);
    expect(result[0].name).toBe('你的故事设定很丰富');
    expect(result[1].description).toBe('有些情绪可以直接用行为展现');
  });

  it('空列表 → 空数组', () => {
    expect(syndromesToUserFacing([])).toEqual([]);
  });
});
