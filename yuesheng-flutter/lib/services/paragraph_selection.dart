// ─────────────────────────────────────────────────────────────
// paragraph_selection — A-3 方案 Y：段落选区纯函数
//
// 选段 UI（ExcerptPickerSheet）的点击语义与选段锚点换算。
// 段落基线与 ADR-A3 一致：以 `\n` 切分（见 chat_context_builder.extractParagraphWindow）。
//
// 点击语义（区间 [s, e] 闭区间，0-based）：
//   - 无选区时点 i        → 单段选区 {i, i}
//   - 有选区 {s, e}，点 i < s → 左扩展 {i, e}
//   - 有选区 {s, e}，点 i > e → 右扩展 {s, i}
//   - 有选区 {s, e}，s ≤ i ≤ e → 区间内重锚 {i, i}
// ─────────────────────────────────────────────────────────────

/// 段落点击后更新选区（纯函数，供选段 UI 与单测使用）
/// [start]/[end] 为当前选区（null 表示无选区），[tapped] 为本次点击的段落序号。
/// 返回新选区 (start, end)；不合法输入（tapped < 0）原样返回当前区间。
(int, int) updateParagraphSelection(int? start, int? end, int tapped) {
  if (tapped < 0) {
    return (start ?? 0, end ?? 0);
  }
  if (start == null || end == null) {
    return (tapped, tapped);
  }
  if (tapped < start) return (tapped, end);
  if (tapped > end) return (start, tapped);
  // 区间内点击 → 重锚到该段（重新选起点）
  return (tapped, tapped);
}

/// 选区字数（区间内段落长度之和，含区间内换行）
int selectionCharCount(List<String> paragraphs, int start, int end) {
  if (paragraphs.isEmpty) return 0;
  final s = start.clamp(0, paragraphs.length - 1);
  final e = end.clamp(s, paragraphs.length - 1);
  var count = 0;
  for (var i = s; i <= e; i++) {
    count += paragraphs[i].length;
  }
  if (e > s) count += e - s; // 段间换行
  return count;
}
