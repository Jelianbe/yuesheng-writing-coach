/**
 * 测试断言辅助函数
 */

import { expect } from 'vitest';
import type { DiagnosisEntry, TeachingState, ActiveProblem } from '../../shared/types/index';

/** 诊断结果断言 */
export function assertValidDiagnosisEntry(entry: DiagnosisEntry) {
  expect(entry).toBeDefined();
  expect(entry.sessionId).toBeTruthy();
  expect(entry.syndromes).toBeInstanceOf(Array);
  expect(entry.syndromes.length).toBeGreaterThan(0);
  expect(entry.confidence).toBeGreaterThanOrEqual(0);
  expect(entry.confidence).toBeLessThanOrEqual(1);
  expect(entry.timestamp).toBeTruthy();

  // 验证每个症候的结构
  for (const syndrome of entry.syndromes) {
    expect(syndrome.id).toBeTruthy();
    expect(syndrome.name).toBeTruthy();
    expect(['L1', 'L2', 'L3']).toContain(syndrome.severity);
    expect(syndrome.evidence).toBeInstanceOf(Array);
  }
}

/** 教学状态断言 */
export function assertValidTeachingState(state: TeachingState) {
  expect(state).toBeDefined();
  expect(state.sessionId).toBeTruthy();
  expect(state.currentPhase).toBeTruthy();
  expect(state.currentSubphase).toBeTruthy();
  expect(state.completedActions).toBeInstanceOf(Array);
  expect(state.activeProblems).toBeInstanceOf(Array);
}

/** 活跃问题断言 */
export function assertValidActiveProblem(problem: ActiveProblem) {
  expect(problem).toBeDefined();
  expect(problem.id).toBeTruthy();
  expect(problem.name).toBeTruthy();
  expect(['L1', 'L2', 'L3']).toContain(problem.severity);
  expect(['active', 'improving', 'resolved']).toContain(problem.status);
  expect(problem.evidence).toBeInstanceOf(Array);
  expect(problem.evidence.length).toBeGreaterThan(0);
}

/** IPC 调用结果断言 */
export function assertIpcSuccess(result: Record<string, unknown>) {
  expect(result).toBeDefined();
  expect(result.success).toBe(true);
}

export function assertIpcError(result: Record<string, unknown>) {
  expect(result).toBeDefined();
  expect(result.success).toBe(false);
  expect(result.error).toBeTruthy();
}
