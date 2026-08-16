// ─────────────────────────────────────────────────────────────
// ParagraphFormatFormatter — 段落格式自动补全（批次88-4）
//
// 排版设置「自动首行缩进 / 段间空行」开启时，在输入路径生效：
//   - 自动首行缩进：回车换行后，新段首自动补两个全角空格
//   - 段间空行：回车后段落之间自动留出空行（'\n' → '\n\n'）
// 只影响 IME/软键盘输入事件；程序化 set（查找替换、快捷短语、
// 版本恢复）零干扰。两个开关可独立开合。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';

import '../utils/paragraph_format.dart';

class ParagraphFormatFormatter extends TextInputFormatter {
  /// 自动首行缩进
  final bool indentOn;

  /// 段间空行
  final bool blankLineOn;

  const ParagraphFormatFormatter({
    required this.indentOn,
    required this.blankLineOn,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!indentOn && !blankLineOn) return newValue;

    final oldText = oldValue.text;
    final newText = newValue.text;

    // 找出插入片段（共同前缀/后缀之差）
    var start = 0;
    while (start < oldText.length &&
        start < newText.length &&
        oldText[start] == newText[start]) {
      start++;
    }
    var oldEnd = oldText.length;
    var newEnd = newText.length;
    while (oldEnd > start &&
        newEnd > start &&
        oldText[oldEnd - 1] == newText[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }
    final inserted = newText.substring(start, newEnd);
    if (!inserted.contains('\n')) return newValue;

    // 展开插入片段中的换行：
    //   '\n' → (空行开关) '\n\n' → (缩进开关) 补 '\u3000\u3000'（段首非空白时）
    final sb = StringBuffer();
    var shift = 0; // 相对原插入片段扩增的字符数
    for (var i = 0; i < inserted.length; i++) {
      final ch = inserted[i];
      sb.write(ch);
      if (ch != '\n') continue;
      if (blankLineOn) {
        sb.write('\n');
        shift++;
      }
      if (indentOn) {
        // 新段首字符（插入片段内下一个，或插入片段外紧跟的字符）
        final charAfter = i + 1 < inserted.length
            ? inserted[i + 1]
            : (newEnd < newText.length ? newText[newEnd] : null);
        final alreadyIndented =
            charAfter == '\u3000' || charAfter == ' ' || charAfter == '\n';
        if (!alreadyIndented) {
          sb.write(paragraphIndent);
          shift += paragraphIndent.length;
        }
      }
    }

    final finalText =
        newText.substring(0, start) + sb.toString() + newText.substring(newEnd);
    if (finalText == newText) return newValue;

    final selection = newValue.selection;
    if (!selection.isValid) {
      return TextEditingValue(
        text: finalText,
        selection: TextSelection.collapsed(offset: start + sb.length),
      );
    }
    // 光标在插入片段末尾/其后 → 平移扩增量；在片段前 → 不动
    int adjust(int offset) =>
        offset >= start + inserted.length ? offset + shift : offset;
    return TextEditingValue(
      text: finalText,
      selection: TextSelection(
        baseOffset: adjust(selection.baseOffset),
        extentOffset: adjust(selection.extentOffset),
      ),
    );
  }
}
