/**
 * 严重度工具函数
 *
 * 统一全项目的严重度←→数值转换，消除重复实现。
 * 规则：L1=1, L2=2, L3=3（数值越大越严重）
 */

import type { SeverityLevel } from '../renderer/shared/types';

/**
 * 严重度转为数值
 * L1=1, L2=2, L3=3
 */
export function severityToNumber(severity: SeverityLevel | 'L1' | 'L2' | 'L3'): number {
  return severity === 'L3' ? 3 : severity === 'L2' ? 2 : 1;
}

/**
 * 严重度→诊断分数映射（非线性，用于能力画像）
 * L1=85（轻微）, L2=55（中等）, L3=20（严重）
 */
export const SEVERITY_TO_SCORE: Record<SeverityLevel, number> = {
  L1: 85,
  L2: 55,
  L3: 20,
};

/** 严重度→枚举数值映射 */
export const SEVERITY_TO_NUM: Record<SeverityLevel, number> = {
  L1: 1,
  L2: 2,
  L3: 3,
};
