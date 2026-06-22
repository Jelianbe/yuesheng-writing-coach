/**
 * Condition Evaluator — 运行时条件评估器
 *
 * 职责：
 * 1. 根据 RuntimeContext 评估 LoadCondition 列表
 * 2. 所有 condition 用 AND 语义（all must pass）
 * 3. 缺失的 context 字段视为 fail（保守策略）
 * 4. 不支持的 condition type 抛 warning 但不阻塞
 *
 * 设计依据：Sprint 14 方向 C 草案 §四（T14-5）
 *
 * Condition 类型：
 * - evidence.quality IN/NOT_IN [low, medium, high]
 * - user.safetyWord IS/IS_NOT boolean
 * - user.dominantSyndrome EQ/NEQ syndromeId
 *
 * Sprint 14 计划（参见 dev-docs/designs/sprint-14-plan.md §四 T14-5）
 */

import type { LoadCondition } from './skill-metadata';

/** 运行时上下文（调用方注入） */
export interface RuntimeContext {
  /** 当前 evidence 质量（来自诊断结果） */
  evidenceQuality?: 'low' | 'medium' | 'high';
  /** 用户是否触发了安全词（如"轻一点"） */
  safetyWord?: boolean;
  /** 用户当前的主要认知症结 ID（来自 AuthorProfile） */
  dominantSyndrome?: string;
}

/** 评估结果 */
export interface EvaluationResult {
  /** 是否所有 condition 都满足 */
  passed: boolean;
  /** 失败的 condition 描述（用于日志） */
  failedConditions: string[];
}

/**
 * 评估 condition 列表
 * @param conditions 条件列表（AND 语义）
 * @param ctx 运行时上下文
 * @returns 是否通过 + 失败详情
 */
export function evaluateConditions(
  conditions: LoadCondition[] | undefined,
  ctx: RuntimeContext,
): EvaluationResult {
  // 无条件 = 默认通过
  if (!conditions || conditions.length === 0) {
    return { passed: true, failedConditions: [] };
  }

  const failed: string[] = [];
  for (const cond of conditions) {
    if (!evaluateSingle(cond, ctx)) {
      failed.push(describeCondition(cond));
    }
  }

  return {
    passed: failed.length === 0,
    failedConditions: failed,
  };
}

/**
 * 评估单个 condition
 * @internal
 */
function evaluateSingle(cond: LoadCondition, ctx: RuntimeContext): boolean {
  switch (cond.type) {
    case 'evidence.quality': {
      // 缺失 evidence.quality 视为 fail
      if (ctx.evidenceQuality === undefined) return false;
      if (cond.op === 'IN') return cond.values.includes(ctx.evidenceQuality);
      if (cond.op === 'NOT_IN') return !cond.values.includes(ctx.evidenceQuality);
      return false;
    }
    case 'user.safetyWord': {
      // 缺失 safetyWord 视为 fail（保守：默认未触发）
      if (ctx.safetyWord === undefined) return false;
      if (cond.op === 'IS') return ctx.safetyWord === cond.value;
      if (cond.op === 'IS_NOT') return ctx.safetyWord !== cond.value;
      return false;
    }
    case 'user.dominantSyndrome': {
      // 缺失 syndrome 视为 fail
      if (ctx.dominantSyndrome === undefined) return false;
      if (cond.op === 'EQ') return ctx.dominantSyndrome === cond.syndromeId;
      if (cond.op === 'NEQ') return ctx.dominantSyndrome !== cond.syndromeId;
      return false;
    }
    default: {
      // 未知 condition type：抛 warning，视为 fail
      const exhaustive: never = cond;
      console.warn(`[ConditionEvaluator] Unknown condition type: ${JSON.stringify(exhaustive)}`);
      return false;
    }
  }
}

/**
 * 描述 condition（用于日志/失败信息）
 * @internal
 */
function describeCondition(cond: LoadCondition): string {
  switch (cond.type) {
    case 'evidence.quality':
      return `evidence.quality ${cond.op} [${cond.values.join(', ')}]`;
    case 'user.safetyWord':
      return `user.safetyWord ${cond.op} ${cond.value}`;
    case 'user.dominantSyndrome':
      return `user.dominantSyndrome ${cond.op} ${cond.syndromeId}`;
  }
}

/**
 * 便捷函数：仅返回 bool（适合 dispatcher 过滤）
 */
export function matchesConditions(
  conditions: LoadCondition[] | undefined,
  ctx: RuntimeContext,
): boolean {
  return evaluateConditions(conditions, ctx).passed;
}
