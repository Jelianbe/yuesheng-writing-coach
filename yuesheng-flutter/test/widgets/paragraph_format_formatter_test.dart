// ─────────────────────────────────────────────────────────────
// ParagraphFormatFormatter 测试 — 批次88-4 输入时自动段落格式
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/paragraph_format_formatter.dart';

TextEditingValue _v(String text, {int caret = -1}) {
  return TextEditingValue(
    text: text,
    selection: caret < 0
        ? TextSelection.collapsed(offset: text.length)
        : TextSelection.collapsed(offset: caret),
  );
}

void main() {
  group('自动首行缩进（indentOn）', () {
    const f = ParagraphFormatFormatter(indentOn: true, blankLineOn: false);

    test('回车 → 新段首补两格全角空格，光标在其后', () {
      final out = f.formatEditUpdate(_v('第一段。'), _v('第一段。\n'));
      expect(out.text, '第一段。\n\u3000\u3000');
      expect(out.selection.baseOffset, out.text.length);
    });

    test('已有缩进的行不再重复补', () {
      final out = f.formatEditUpdate(_v('第一段。'), _v('第一段。\n\u3000第二段'));
      expect(out.text, '第一段。\n\u3000第二段');
    });

    test('无换行的普通输入不受影响', () {
      final out = f.formatEditUpdate(_v('一'), _v('一二'));
      expect(out.text, '一二');
    });

    test('删除文本不受影响', () {
      final out = f.formatEditUpdate(_v('一二'), _v('一'));
      expect(out.text, '一');
    });
  });

  group('段间空行（blankLineOn）', () {
    const f = ParagraphFormatFormatter(indentOn: false, blankLineOn: true);

    test('回车 → 段间自动补空行', () {
      final out = f.formatEditUpdate(_v('第一段。'), _v('第一段。\n'));
      expect(out.text, '第一段。\n\n');
      expect(out.selection.baseOffset, out.text.length);
    });
  });

  group('两开关组合', () {
    const f = ParagraphFormatFormatter(indentOn: true, blankLineOn: true);

    test('回车 → 空行 + 新段缩进', () {
      final out = f.formatEditUpdate(_v('第一段。'), _v('第一段。\n'));
      expect(out.text, '第一段。\n\n\u3000\u3000');
      expect(out.selection.baseOffset, out.text.length);
    });
  });

  group('两开关全关', () {
    const f = ParagraphFormatFormatter(indentOn: false, blankLineOn: false);

    test('回车原样返回', () {
      final out = f.formatEditUpdate(_v('第一段。'), _v('第一段。\n'));
      expect(out.text, '第一段。\n');
    });
  });
}
