// ─────────────────────────────────────────────────────────────
// 行段聚焦感知的编辑器控制器（批次85-2）
// 从 writing_page.dart 拆出，避免写作页成为「上帝组件」。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// 返回 [cursor] 所在段落（按 '\n' 分隔）在 [text] 中的 [start, end) 区间
/// （批次85-2 行段聚焦：淡化光标所在段以外的内容）
({int start, int end}) currentSegmentRange(String text, int cursor) {
  if (text.isEmpty) return (start: 0, end: 0);
  final clamped = cursor < 0
      ? 0
      : (cursor > text.length ? text.length : cursor);
  final start = clamped == 0 ? 0 : text.lastIndexOf('\n', clamped - 1) + 1;
  final nl = text.indexOf('\n', clamped);
  final end = nl == -1 ? text.length : nl;
  return (start: start, end: end);
}

/// 行段聚焦感知的编辑器控制器（批次85-2）：
/// 开启 [focusMode] 且光标为折叠态时，把光标所在段以外的文字渲染为淡化色，
/// 当前段保持正常（沉浸专注，对标 iA Writer）；有选区时不淡化。
class FocusAwareEditingController extends TextEditingController {
  bool focusMode = false;

  FocusAwareEditingController({String? text}) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    if (!focusMode ||
        text.isEmpty ||
        !selection.isValid ||
        !selection.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final seg = currentSegmentRange(text, selection.start);
    final dimmed = style?.copyWith(color: style.color?.withValues(alpha: 0.32));
    return TextSpan(
      style: style,
      children: [
        if (seg.start > 0)
          TextSpan(text: text.substring(0, seg.start), style: dimmed),
        TextSpan(text: text.substring(seg.start, seg.end)),
        if (seg.end < text.length)
          TextSpan(text: text.substring(seg.end), style: dimmed),
      ],
    );
  }
}
