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

  // ── D3-b 早退护栏（2026-09-21）：行为零变化 + 判据不得退化为「长度/计数」──
  // 判据取舍与反例证明见 `lib/widgets/paragraph_format_formatter.dart` 文件头。
  group('早退护栏（D3-b）', () {
    const f = ParagraphFormatFormatter(indentOn: true, blankLineOn: true);

    test('尾部追写且尾部无换行 → 原样返回', () {
      final out = f.formatEditUpdate(_v('第一章\n正文一'), _v('第一章\n正文一二'));
      expect(out.text, '第一章\n正文一二');
    });

    test('尾部追写且尾部含换行 → 仍须展开（早退不得吃掉回车）', () {
      final out = f.formatEditUpdate(_v('第一章\n正文一'), _v('第一章\n正文一\n'));
      expect(out.text, '第一章\n正文一\n\n\u3000\u3000');
    });

    test('尾部纯删 → 原样返回', () {
      final out = f.formatEditUpdate(_v('第一章\n正文一'), _v('第一章\n正文'));
      expect(out.text, '第一章\n正文');
    });

    test('中部插入（非尾部）→ 仍走原路径并正确展开', () {
      final out = f.formatEditUpdate(_v('甲乙'), _v('甲\n乙'));
      expect(out.text, '甲\n\n\u3000\u3000乙');
    });

    // ★ 判别性用例：长度 3→3、'\n' 计数 1→1 **均未变化**，但插入片段
    // `'p\nq'` 含 '\n' ⇒ 必须展开。若把早退判据写成「长度/计数」类
    // （含照抄回收板的「净缩短 ⇒ 无插入」），本例会转红。
    test('中部替换：长度与换行计数均不变，仍须展开', () {
      final out = f.formatEditUpdate(_v('x\ny'), _v('p\nq'));
      expect(out.text, 'p\n\n\u3000\u3000q');
    });
  });
}
