// ─────────────────────────────────────────────────────────────
// ParagraphFormatFormatter — 段落格式自动补全（批次88-4）
//
// 排版设置「自动首行缩进 / 段间空行」开启时，在输入路径生效：
//   - 自动首行缩进：回车换行后，新段首自动补两个全角空格
//   - 段间空行：回车后段落之间自动留出空行（'\n' → '\n\n'）
// 只影响 IME/软键盘输入事件；程序化 set（查找替换、快捷短语、
// 版本恢复）零干扰。两个开关可独立开合。
//
// ── 编辑器性能（2026-09-21 · D3-b）：早退护栏的**判据取舍**（读改动前必读）──
//
// 背景：本格式化器只可能改动「插入片段含 `'\n'`」的编辑（唯一出口 =
// `if (!inserted.contains('\n')) return newValue;`）。而「插入片段」必须由
// **两趟 Dart 级逐字符前后缀扫描**才能定位 ⇒ 每次击键先付一次 O(全文) 扫描。
// `blankLineOn` 默认关、**`indentOn` 默认开**（`writing_providers.dart:697`
// `indentParagraph: indent == null || indent == '1'`）⇒ 该扫描**默认就付**。
//
// ⚠️ 判据不能照抄回收板：`deleted_text_extractor.dart:13` 的
// `if (newText.length >= oldText.length) return null;` 之所以成立，是因为它的
// **被调方契约本身就要求「纯删除」**（净缩短是纯删除的必要条件）。
//
// 更强的一条：**任何只依据「长度 / `'\n'` 计数」的判据都不成立**。反例（两个
// 编辑的 `(Δ长度, Δ'\n'数)` 完全相同 `(+1, 0)`，但插入片段一个无换行、一个有）：
//   a) `'一' → '一二'`        插入片段 `'二'`   ⇒ 无 '\n'
//   b) 把 `'\n'` 替换为 `'a\n'` 插入片段 `'a\n'` ⇒ **有 '\n'**
// ⇒ 同理，「净缩短 ⇒ 无插入」也不成立：替换型编辑净长度可不变甚至变长
//   （`'x\ny' → 'p\nq'`：长度 3→3、`'\n'` 数 1→1，插入片段 `'p\nq'` **含** `'\n'`）。
//
// ⇒ 因此只用**结构上确凿**的两种形态做早退（[_insertedRegionCannotMatter]）：
//   ① 尾部追写 `newText == oldText + tail`；② 尾部纯删 `oldText == newText + tail`。
//   二者**不是近似**，而是与原扫描**逐字等价**：前缀扫描必然走到 `oldText.length`、
//   后缀扫描必然 0 轮，插入片段**恰是** `tail`（①）或**恰为空**（②）。
//   其余形态（中部插入 / 替换 / 混合）**一律走原路径**，不做启发式猜测。
//
// 判别性用例：`test/widgets/paragraph_format_formatter_test.dart`
// `'中部替换：长度与 '\n' 计数均不变，仍须展开'` —— 若有人把判据换成
// 「长度/计数」，该例会转红。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';

import '../utils/paragraph_format.dart';

/// 早退判据：本次编辑**不可能**产生需要展开的插入片段（详见文件头注释）。
///
/// 只在两种**结构确凿**的形态上返回 true，二者均与原前后缀扫描逐字等价；
/// 其余形态一律返回 false（交给原路径，不做启发式猜测）。
bool _insertedRegionCannotMatter(String oldText, String newText) {
  if (newText.length > oldText.length) {
    // 尾部追写：插入片段恰为尾部 ⇒ 只看尾部有无换行
    return newText.startsWith(oldText) &&
        !newText.substring(oldText.length).contains('\n');
  }
  if (newText.length < oldText.length) {
    // 尾部纯删：插入片段恰为空
    return oldText.startsWith(newText);
  }
  return false;
}

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
    if (_insertedRegionCannotMatter(oldText, newText)) return newValue;

    final region = _findInsertedRegion(oldText, newText);
    if (!region.inserted.contains('\n')) return newValue;

    final expanded = _expandInserted(
      region.inserted,
      newText,
      region.newEnd,
      indentOn: indentOn,
      blankLineOn: blankLineOn,
    );
    final finalText =
        newText.substring(0, region.start) +
        expanded.text +
        newText.substring(region.newEnd);
    if (finalText == newText) return newValue;

    final selection = newValue.selection;
    if (!selection.isValid) {
      return TextEditingValue(
        text: finalText,
        selection: TextSelection.collapsed(
          offset: region.start + expanded.text.length,
        ),
      );
    }
    // 光标在插入片段末尾/其后 → 平移扩增量；在片段前 → 不动
    int adjust(int offset) => offset >= region.start + region.inserted.length
        ? offset + expanded.shift
        : offset;
    return TextEditingValue(
      text: finalText,
      selection: TextSelection(
        baseOffset: adjust(selection.baseOffset),
        extentOffset: adjust(selection.extentOffset),
      ),
    );
  }

  ({int start, int oldEnd, int newEnd, String inserted}) _findInsertedRegion(
    String oldText,
    String newText,
  ) {
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
    return (
      start: start,
      oldEnd: oldEnd,
      newEnd: newEnd,
      inserted: newText.substring(start, newEnd),
    );
  }

  ({String text, int shift}) _expandInserted(
    String inserted,
    String newText,
    int newEnd, {
    required bool indentOn,
    required bool blankLineOn,
  }) {
    final sb = StringBuffer();
    var shift = 0;
    for (var i = 0; i < inserted.length; i++) {
      final ch = inserted[i];
      sb.write(ch);
      if (ch != '\n') continue;
      if (blankLineOn) {
        sb.write('\n');
        shift++;
      }
      if (indentOn) {
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
    return (text: sb.toString(), shift: shift);
  }
}
