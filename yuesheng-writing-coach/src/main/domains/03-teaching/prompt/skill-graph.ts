/**
 * Skill 依赖图校验器
 *
 * 职责：
 * 1. 检测 SKILL 之间的循环依赖
 * 2. 检测 SKILL 缺失依赖（depends 引用了不存在的 id）
 * 3. 启动时 fail-fast，避免运行时才暴露
 *
 * 设计依据：Sprint 14 方向 C 草案 §五
 */

import type { Skill } from './skill-metadata';

/** 校验结果 */
export interface ValidationResult {
  valid: boolean;
  errors: string[];
  cycles: string[][];
  missingDeps: Array<{ from: string; to: string }>;
}

/** 空校验结果（合法状态） */
const EMPTY_RESULT: ValidationResult = {
  valid: true,
  errors: [],
  cycles: [],
  missingDeps: [],
};

/**
 * 校验 SKILL 依赖图
 * @param skills 已加载的 SKILL 列表
 * @returns 校验结果（包含错误、循环、缺失依赖）
 */
export function validateSkillGraph(skills: Skill[]): ValidationResult {
  if (skills.length === 0) {
    return EMPTY_RESULT;
  }

  const idIndex = new Map(skills.map(s => [s.meta.id, s]));
  const result: ValidationResult = {
    valid: true,
    errors: [],
    cycles: [],
    missingDeps: [],
  };

  // 1. 检测缺失依赖
  for (const skill of skills) {
    const deps = skill.meta.depends ?? [];
    for (const depId of deps) {
      if (!idIndex.has(depId)) {
        result.missingDeps.push({ from: skill.meta.id, to: depId });
        result.errors.push(
          `[SkillGraph] SKILL "${skill.meta.id}" depends on missing SKILL "${depId}"`,
        );
      }
    }
  }

  // 2. 检测循环依赖（DFS）
  const cycles = findCycles(skills, idIndex);
  if (cycles.length > 0) {
    result.cycles = cycles;
    for (const cycle of cycles) {
      result.errors.push(
        `[SkillGraph] Circular dependency detected: ${cycle.join(' → ')} → ${cycle[0]}`,
      );
    }
  }

  result.valid = result.errors.length === 0;
  return result;
}

/**
 * DFS 查找循环依赖
 * @returns 循环路径列表（每个循环至少 2 个节点）
 */
function findCycles(
  skills: Skill[],
  idIndex: Map<string, Skill>,
): string[][] {
  const cycles: string[][] = [];
  const visited = new Set<string>();
  const stack: string[] = [];
  const stackSet = new Set<string>();

  function dfs(nodeId: string): void {
    if (stackSet.has(nodeId)) {
      // 找到循环：提取 stack 中从 nodeId 开始的子序列
      const cycleStart = stack.indexOf(nodeId);
      if (cycleStart >= 0) {
        cycles.push(stack.slice(cycleStart));
      }
      return;
    }
    if (visited.has(nodeId)) {
      return;
    }

    visited.add(nodeId);
    stackSet.add(nodeId);
    stack.push(nodeId);

    const node = idIndex.get(nodeId);
    if (node) {
      const deps = node.meta.depends ?? [];
      for (const dep of deps) {
        if (idIndex.has(dep)) {
          dfs(dep);
        }
      }
    }

    stack.pop();
    stackSet.delete(nodeId);
  }

  for (const skill of skills) {
    if (!visited.has(skill.meta.id)) {
      dfs(skill.meta.id);
    }
  }

  return cycles;
}

/**
 * 启动时 fail-fast 校验
 * 抛出带所有错误的 Error
 */
export function assertSkillGraphValid(skills: Skill[]): void {
  const result = validateSkillGraph(skills);
  if (!result.valid) {
    throw new Error(
      `[SkillGraph] Invalid SKILL dependency graph:\n${result.errors.join('\n')}`,
    );
  }
}
