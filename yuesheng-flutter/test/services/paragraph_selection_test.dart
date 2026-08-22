// ─────────────────────────────────────────────────────────────
// paragraph_selection 纯函数测试 — A-3 方案 Y 选段点击语义
//
// 覆盖：无选区首点 / 左右扩展 / 区间内重锚 / 边界等值 / 非法输入 /
//       selectionCharCount 含段间换行与 clamp
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/paragraph_selection.dart';

void main() {
  group('updateParagraphSelection', () {
    test('无选区 → 首点成单段选区 {i, i}', () {
      expect(updateParagraphSelection(null, null, 3), (3, 3));
      expect(updateParagraphSelection(null, null, 0), (0, 0));
    });

    test('点选区左侧 → 左扩展', () {
      expect(updateParagraphSelection(4, 6, 1), (1, 6));
    });

    test('点选区右侧 → 右扩展', () {
      expect(updateParagraphSelection(4, 6, 9), (4, 9));
    });

    test('点选区内（含端点）→ 重锚为单段', () {
      expect(updateParagraphSelection(4, 6, 5), (5, 5));
      expect(updateParagraphSelection(4, 6, 4), (4, 4)); // 左端点
      expect(updateParagraphSelection(4, 6, 6), (6, 6)); // 右端点
    });

    test('单段选区再点相邻段 → 扩展为两段', () {
      expect(updateParagraphSelection(2, 2, 3), (2, 3));
      expect(updateParagraphSelection(2, 2, 1), (1, 2));
    });

    test('tapped < 0 非法输入 → 原样返回当前区间（无选区时 (0,0)）', () {
      expect(updateParagraphSelection(2, 5, -1), (2, 5));
      expect(updateParagraphSelection(null, null, -1), (0, 0));
    });
  });

  group('selectionCharCount', () {
    final paras = ['第一段', '第二段内容', '三'];

    test('单段：只计该段长度（无换行）', () {
      expect(selectionCharCount(paras, 1, 1), '第二段内容'.length);
    });

    test('多段：段长求和 + 段间换行数', () {
      final textLen = '第一段'.length + '第二段内容'.length + '三'.length;
      expect(selectionCharCount(paras, 0, 2), textLen + 2); // 2 个段间换行
    });

    test('越界自动 clamp', () {
      expect(selectionCharCount(paras, 0, 99), selectionCharCount(paras, 0, 2));
      expect(selectionCharCount(paras, -5, 1), selectionCharCount(paras, 0, 1));
    });

    test('空段落列表 → 0', () {
      expect(selectionCharCount(const [], 0, 0), 0);
    });
  });
}
