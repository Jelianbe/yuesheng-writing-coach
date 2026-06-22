/**
 * keypassage-validator.test.ts — ADR-003 B-4 验证逻辑单测
 *
 * 覆盖：
 * - 向后兼容：三个 offset 字段全缺失 → 标记为 no_offset_fields，不算错误
 * - 字段类型错误 → 降级（清空 offset 字段）
 * - offset 越界 / 倒序 → 降级
 * - slice 与 text 不一致 → 降级
 * - 正确 offset → 通过
 * - 批量验证：分离 valid / invalid
 * - 不可变性：返回新对象，不修改入参
 * - 防御性：非法入参（NaN / Infinity / 浮点数 / 负数）
 */

import { describe, it, expect } from 'vitest';
import {
  validateKeyPassageOffset,
  validateKeyPassagesBatch,
  type KeyPassageValidationReason,
} from './keypassage-validator';
import type { KeyPassage } from '../../../../shared/types/types-diagnosis';

// ===== 测试 fixtures =====
const CONTENT = '张三走进了古老的森林。他听见身后传来狼的嚎叫，心中一惊。';
//   0       6         14            22                  36
//
// 关键片段：
//   '张三'         → [0, 2)
//   '森林'         → [8, 10)
//   '他听见身后传来狼的嚎叫' → [11, 22)

function makePassage(overrides: Partial<KeyPassage> = {}): KeyPassage {
  return {
    text: '他听见身后传来狼的嚎叫',
    issue: '缺乏具体描写',
    syndromeRef: 'P003',
    chapterId: 'ch-001',
    startOffset: 11,
    endOffset: 22,
    ...overrides,
  };
}

// ===== 单条验证 =====

describe('validateKeyPassageOffset', () => {
  describe('backward compatibility', () => {
    it('三个 offset 字段全缺失 → hasValidOffset=false, reason=no_offset_fields（不视为错误）', () => {
      const passage: KeyPassage = {
        text: '他听见身后传来狼的嚎叫',
        issue: '缺乏具体描写',
        syndromeRef: 'P003',
      };
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe<KeyPassageValidationReason>('no_offset_fields');
      // 不修改入参
      expect(result.passage).toBe(passage);
    });

    it('三个 offset 字段全缺失 + 无 content → 同样通过 no_offset_fields', () => {
      const passage: KeyPassage = { text: '片段', issue: '问题' };
      const result = validateKeyPassageOffset(passage);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('no_offset_fields');
    });
  });

  describe('incomplete offset (部分字段缺失)', () => {
    it('只有 chapterId + startOffset（缺 endOffset）→ 降级', () => {
      const passage: KeyPassage = {
        text: '片段', issue: '问题', chapterId: 'ch-001', startOffset: 10,
      };
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('incomplete_offset');
      expect(result.passage.chapterId).toBeUndefined();
      expect(result.passage.startOffset).toBeUndefined();
      expect(result.passage.endOffset).toBeUndefined();
    });

    it('只有 startOffset + endOffset（缺 chapterId）→ 降级', () => {
      const passage: KeyPassage = {
        text: '片段', issue: '问题', startOffset: 10, endOffset: 20,
      };
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('incomplete_offset');
    });
  });

  describe('invalid types', () => {
    it('chapterId 是空字符串 → 降级', () => {
      const passage = makePassage({ chapterId: '' });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('invalid_type');
    });

    it('startOffset 是浮点数 → 降级', () => {
      const passage = makePassage({ startOffset: 10.5 });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('invalid_type');
    });

    it('startOffset 是 NaN → 降级', () => {
      const passage = makePassage({ startOffset: NaN });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('invalid_type');
    });

    it('endOffset 是 Infinity → 降级', () => {
      const passage = makePassage({ endOffset: Infinity });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('invalid_type');
    });

    it('startOffset 是负数（无 content）→ 需提供 content 才能检测越界', () => {
      const passage = makePassage({ startOffset: -5 });
      const result = validateKeyPassageOffset(passage);
      // 无 content 验证时，只检查 reversed_range（endOffset > startOffset）
      expect(result.hasValidOffset).toBe(true);
    });

    it('startOffset 是负数 + 提供 content → 降级为 out_of_range', () => {
      const passage = makePassage({ startOffset: -5 });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('out_of_range');
    });
  });

  describe('reversed range', () => {
    it('endOffset === startOffset → 降级', () => {
      const passage = makePassage({ startOffset: 10, endOffset: 10 });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('reversed_range');
    });

    it('endOffset < startOffset → 降级', () => {
      const passage = makePassage({ startOffset: 20, endOffset: 10 });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('reversed_range');
    });
  });

  describe('out of range', () => {
    it('endOffset 超出 content 长度 → 降级', () => {
      const passage = makePassage({ startOffset: 30, endOffset: 1000 });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('out_of_range');
    });

    it('无 content 时跳过越界检查（信任调用方）', () => {
      const passage = makePassage({ startOffset: 30, endOffset: 1000 });
      const result = validateKeyPassageOffset(passage);
      expect(result.hasValidOffset).toBe(true);
    });
  });

  describe('text mismatch', () => {
    it('slice 与 text 不一致 → 降级', () => {
      const passage = makePassage({ text: '完全不同的文本' });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('text_mismatch');
    });

    it('slice 与 text 差一个标点 → 降级', () => {
      const passage = makePassage({ text: '他听见身后传来狼的嚎叫!' }); // 末尾是英文 !
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(false);
      expect(result.reason).toBe('text_mismatch');
    });
  });

  describe('valid cases', () => {
    it('正确 offset + 提供 content → 通过', () => {
      const passage = makePassage();
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(true);
      expect(result.reason).toBeUndefined();
      expect(result.passage).toEqual(passage);
    });

    it('正确 offset + 不提供 content → 通过（无精确验证）', () => {
      const passage = makePassage();
      const result = validateKeyPassageOffset(passage);
      expect(result.hasValidOffset).toBe(true);
    });

    it('正确 offset + 边界：startOffset === 0', () => {
      const passage = makePassage({ text: '张三', startOffset: 0, endOffset: 2 });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(true);
    });

    it('正确 offset + 边界：endOffset === content.length', () => {
      const lastChar = CONTENT[CONTENT.length - 1];
      const passage = makePassage({
        text: lastChar,
        startOffset: CONTENT.length - 1,
        endOffset: CONTENT.length,
      });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.hasValidOffset).toBe(true);
    });
  });

  describe('immutability', () => {
    it('验证失败时返回新对象，不修改入参', () => {
      const original = makePassage({ startOffset: 10.5 });
      const snapshot = JSON.stringify(original);
      validateKeyPassageOffset(original, CONTENT);
      expect(JSON.stringify(original)).toBe(snapshot);
    });

    it('降级后的 passage 不再包含 offset 字段', () => {
      const passage = makePassage({ startOffset: 10.5 });
      const result = validateKeyPassageOffset(passage, CONTENT);
      expect(result.passage.chapterId).toBeUndefined();
      expect(result.passage.startOffset).toBeUndefined();
      expect(result.passage.endOffset).toBeUndefined();
      // 但 text / issue / syndromeRef 保留
      expect(result.passage.text).toBe(passage.text);
      expect(result.passage.issue).toBe(passage.issue);
      expect(result.passage.syndromeRef).toBe(passage.syndromeRef);
    });
  });
});

// ===== 批量验证 =====

describe('validateKeyPassagesBatch', () => {
  it('分离 valid 与 invalid（no_offset_fields 不计为 invalid）', () => {
    const passages: KeyPassage[] = [
      makePassage(),                                                    // 有效
      { text: '片段', issue: '问题' },                                    // no_offset_fields（兼容）
      makePassage({ startOffset: 10.5 }),                                // invalid_type
      makePassage({ endOffset: 5 }),                                     // reversed_range
    ];
    const result = validateKeyPassagesBatch(passages, CONTENT);
    expect(result.valid).toHaveLength(1);
    expect(result.invalid).toHaveLength(2); // 2 个真正错误的
  });

  it('空数组 → valid=[], invalid=[]', () => {
    const result = validateKeyPassagesBatch([], CONTENT);
    expect(result.valid).toEqual([]);
    expect(result.invalid).toEqual([]);
  });

  it('全部有 offset 字段 + 全部有效 → valid=N, invalid=[]', () => {
    const passages: KeyPassage[] = [
      makePassage({ text: '张三', startOffset: 0, endOffset: 2 }),
      makePassage({ text: '森林', startOffset: 8, endOffset: 10 }),
    ];
    const result = validateKeyPassagesBatch(passages, CONTENT);
    expect(result.valid).toHaveLength(2);
    expect(result.invalid).toEqual([]);
  });

  it('all text mismatches → valid=[], invalid=N', () => {
    const passages: KeyPassage[] = [
      makePassage({ text: '不对的文本1' }),
      makePassage({ text: '不对的文本2' }),
    ];
    const result = validateKeyPassagesBatch(passages, CONTENT);
    expect(result.valid).toEqual([]);
    expect(result.invalid).toHaveLength(2);
  });
});
