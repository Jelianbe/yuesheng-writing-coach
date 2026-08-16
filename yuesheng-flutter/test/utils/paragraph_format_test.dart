// ─────────────────────────────────────────────────────────────
// paragraph_format 测试 — 批次88-4 段落格式批量处理
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/utils/paragraph_format.dart';

void main() {
  group('indentParagraphs', () {
    test('单段无缩进 → 补两格全角空格', () {
      expect(indentParagraphs('第一段内容。'), '\u3000\u3000第一段内容。');
    });

    test('已缩进的段跳过', () {
      expect(indentParagraphs('\u3000\u3000第一段。'), '\u3000\u3000第一段。');
    });

    test('多段逐段补缩进，空段跳过', () {
      expect(
        indentParagraphs('一段。\n\n二段。'),
        '\u3000\u3000一段。\n\n\u3000\u3000二段。',
      );
    });

    test('空文本返回空', () {
      expect(indentParagraphs(''), '');
    });
  });

  group('removeParagraphIndent', () {
    test('移除每段开头缩进', () {
      expect(
        removeParagraphIndent('\u3000\u3000一段。\n\u3000\u3000二段。'),
        '一段。\n二段。',
      );
    });

    test('半角空格前缀也移除', () {
      expect(removeParagraphIndent('  一段。'), '一段。');
    });

    test('无缩进原样返回', () {
      expect(removeParagraphIndent('一段。'), '一段。');
    });
  });

  group('addBlankLineBetween', () {
    test('每段后补一个空行', () {
      expect(addBlankLineBetween('一段。\n二段。'), '一段。\n\n二段。');
    });

    test('已有连续换行先压缩再补', () {
      expect(addBlankLineBetween('一段。\n\n\n二段。'), '一段。\n\n二段。');
    });

    test('单段无换行原样返回', () {
      expect(addBlankLineBetween('一段。'), '一段。');
    });
  });

  group('removeBlankLineBetween', () {
    test('连续换行压缩为单个', () {
      expect(removeBlankLineBetween('一段。\n\n\n二段。'), '一段。\n二段。');
    });

    test('无空行原样返回', () {
      expect(removeBlankLineBetween('一段。\n二段。'), '一段。\n二段。');
    });
  });
}
