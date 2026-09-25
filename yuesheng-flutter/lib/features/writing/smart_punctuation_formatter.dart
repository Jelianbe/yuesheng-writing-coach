// ─────────────────────────────────────────────────────────────
// SmartPunctuationFormatter — 智能标点（批次85-6 自动补全/句末标点）
// 对标写作天下「智能引号/自动标点」范式，移动端减机械操作。
//
// 规则（保守，只做可预期、不易误伤的两种）：
//   1. 自动补全：输入左配对符（「《【（“‘）→ 自动补上右配对符，
//      光标停在两者中间，继续书写。
//   2. 智能跳过：光标恰好在相同右配对符之前、再输入该右符时，
//      不重复插入，光标直接跳到右符之后（写完一句话想"跳出引号"）。
// 刻意不做「语气词后自动加标点」等易误判规则（用户偏好保守）。
//
// 实现走 TextInputFormatter（仅影响软键盘/IME 输入事件），
// 对程序化 set（查找替换、快捷短语插入、版本恢复）零干扰。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';

class SmartPunctuationFormatter extends TextInputFormatter {
  const SmartPunctuationFormatter();

  /// 左配对符 → 右配对符
  static const Map<String, String> _pairs = {
    '「': '」',
    '『': '』',
    '《': '》',
    '【': '】',
    '（': '）',
    '“': '”',
    '‘': '’',
  };

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;
    final oldSel = oldValue.selection;

    // 仅处理"单字符增量输入"：粘贴多字符、删除、IME 组合一次提交整段 → 原样
    if (newText.length != oldText.length + 1) return newValue;
    final sel = newValue.selection;
    if (!sel.isValid || !sel.isCollapsed) return newValue; // 有选区不处理
    final caret = sel.baseOffset;
    if (caret < 1 || caret > newText.length) return newValue;
    final inserted = newText[caret - 1];

    // 1) 左配对符 → 补右符，光标停在中间
    final closer = _pairs[inserted];
    if (closer != null) {
      final text =
          newText.substring(0, caret) + closer + newText.substring(caret);
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret),
      );
    }

    // 2) 右配对符，且输入前光标后紧跟相同右符 → 跳过不重复，光标移到其后
    if (_pairs.containsValue(inserted) &&
        oldSel.isValid &&
        oldSel.isCollapsed &&
        oldSel.baseOffset < oldText.length &&
        oldText[oldSel.baseOffset] == inserted) {
      return TextEditingValue(
        text: oldText,
        selection: TextSelection.collapsed(offset: oldSel.baseOffset + 1),
      );
    }

    return newValue;
  }
}
