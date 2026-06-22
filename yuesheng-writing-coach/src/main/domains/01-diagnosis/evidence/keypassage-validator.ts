/**
 * keypassage-validator.ts — KeyPassage offset 验证（ADR-003 B-4）
 *
 * 职责：
 * 1. 验证 KeyPassage 的 chapterId / startOffset / endOffset 字段合法性
 * 2. 如果提供了原文 content，验证 slice(start, end) === text
 * 3. 验证失败时降级：清空 offset 字段，只保留 text / issue / syndromeRef
 *
 * 设计原则：
 * - 纯函数，无副作用（不读 store / 不写日志）
 * - 容错优先：任何不一致都视为"无 offset"，但 text/issue 必须保留
 * - 不可变：返回新对象，不修改入参
 * - UTF-16 安全：使用 String.slice 语义，不预计算 Array.from
 *
 * 调用方：
 * - diagnosis-parser.ts 解析 AI 输出后调用
 * - training-prompt-loader.ts 在引用 keyPassages 时再次验证
 */

import type { KeyPassage } from '../../../../shared/types/types-diagnosis';

/** 验证结果 */
export interface KeyPassageValidationResult {
  /** 是否拥有有效 offset 溯源信息 */
  hasValidOffset: boolean;
  /** 降级后的 KeyPassage（offset 字段可能已被清空） */
  passage: KeyPassage;
  /** 失败原因（仅 hasValidOffset === false 时设置） */
  reason?: KeyPassageValidationReason;
}

/** 失败原因枚举 */
export type KeyPassageValidationReason =
  | 'no_offset_fields'        // 三个字段都缺失（向后兼容情况，正常）
  | 'incomplete_offset'       // 部分字段缺失（不应部分填充）
  | 'invalid_type'            // 类型错误（非数字）
  | 'out_of_range'            // offset 越界
  | 'reversed_range'          // endOffset <= startOffset
  | 'text_mismatch'           // slice 后与 text 不一致
  ;

/**
 * 验证 KeyPassage 的 offset 字段
 *
 * @param passage - 待验证的 KeyPassage
 * @param content - 原文内容（可选，用于精确验证）
 * @returns 验证结果 + 降级后的 KeyPassage
 */
export function validateKeyPassageOffset(
  passage: KeyPassage,
  content?: string,
): KeyPassageValidationResult {
  const { chapterId, startOffset, endOffset } = passage;

  // 1. 三个字段全部缺失 → 向后兼容情况（老诊断 / LLM 不会输出 offset）
  if (chapterId === undefined && startOffset === undefined && endOffset === undefined) {
    return { hasValidOffset: false, passage, reason: 'no_offset_fields' };
  }

  // 2. 部分缺失 → 数据损坏，降级
  if (chapterId === undefined || startOffset === undefined || endOffset === undefined) {
    return {
      hasValidOffset: false,
      passage: stripOffsetFields(passage),
      reason: 'incomplete_offset',
    };
  }

  // 3. chapterId 必须是非空字符串
  if (typeof chapterId !== 'string' || chapterId.length === 0) {
    return {
      hasValidOffset: false,
      passage: stripOffsetFields(passage),
      reason: 'invalid_type',
    };
  }

  // 4. offset 必须是有限整数
  if (
    typeof startOffset !== 'number' ||
    typeof endOffset !== 'number' ||
    !Number.isFinite(startOffset) ||
    !Number.isFinite(endOffset) ||
    !Number.isInteger(startOffset) ||
    !Number.isInteger(endOffset)
  ) {
    return {
      hasValidOffset: false,
      passage: stripOffsetFields(passage),
      reason: 'invalid_type',
    };
  }

  // 5. endOffset 必须 > startOffset
  if (endOffset <= startOffset) {
    return {
      hasValidOffset: false,
      passage: stripOffsetFields(passage),
      reason: 'reversed_range',
    };
  }

  // 6. 如果提供了原文，验证范围 + slice 一致性
  if (content !== undefined) {
    if (startOffset < 0 || endOffset > content.length) {
      return {
        hasValidOffset: false,
        passage: stripOffsetFields(passage),
        reason: 'out_of_range',
      };
    }
    const slice = content.slice(startOffset, endOffset);
    if (slice !== passage.text) {
      return {
        hasValidOffset: false,
        passage: stripOffsetFields(passage),
        reason: 'text_mismatch',
      };
    }
  }

  // 通过
  return { hasValidOffset: true, passage };
}

/**
 * 去除 offset 字段（保留 text / issue / syndromeRef）
 *
 * 用于验证失败时降级，保证向后兼容。
 */
function stripOffsetFields(passage: KeyPassage): KeyPassage {
  // 浅拷贝避免修改原对象
  const result: KeyPassage = {
    text: passage.text,
    issue: passage.issue,
  };
  if (passage.syndromeRef !== undefined) {
    result.syndromeRef = passage.syndromeRef;
  }
  return result;
}

/**
 * 批量验证：过滤并降级 keyPassages 数组
 *
 * 用法：const validated = validateKeyPassagesBatch(keyPassages, content);
 * 返回：{ valid: KeyPassage[], invalid: KeyPassage[] }
 */
export interface BatchValidationResult {
  valid: KeyPassage[];
  invalid: KeyPassage[];
}

export function validateKeyPassagesBatch(
  passages: readonly KeyPassage[],
  content?: string,
): BatchValidationResult {
  const valid: KeyPassage[] = [];
  const invalid: KeyPassage[] = [];

  for (const p of passages) {
    const result = validateKeyPassageOffset(p, content);
    if (result.hasValidOffset) {
      valid.push(result.passage);
    } else if (result.reason !== 'no_offset_fields') {
      // 'no_offset_fields' 是正常向后兼容，不计入 invalid
      invalid.push(result.passage);
    }
  }

  return { valid, invalid };
}
