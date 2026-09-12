// ─────────────────────────────────────────────────────────────
// 删除片段提取（批次86-1 回收板）——纯函数
//
// C92-6b：原为 `writing_page.dart` 顶层函数，因文档控制器需要而复用，
// 提取为独立纯函数文件（避免控制器反向 import 宿主文件形成库循环）。
// `writing_page.dart` 以 `export` 保持对外的既有可见性（含测试单测）。
// ─────────────────────────────────────────────────────────────

/// 计算 [oldText] → [newText] 变化中被删除的连续片段（批次86-1 回收板）。
/// 仅当变化是"纯删除"（new 是 old 删去一段得到）时返回被删片段（trim 后），
/// 插入 / 替换 / 增删混合返回 null（保守，避免误存）。
String? extractRemovedText(String oldText, String newText) {
  if (newText.length >= oldText.length) return null; // 未变短，非删除
  var prefix = 0;
  final minLen = newText.length;
  while (prefix < minLen && oldText[prefix] == newText[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < minLen - prefix &&
      oldText[oldText.length - 1 - suffix] ==
          newText[newText.length - 1 - suffix]) {
    suffix++;
  }
  // new 的中间段必须为空（纯删除），否则是替换/混合，保守不存
  final newMiddle = newText.substring(prefix, newText.length - suffix);
  if (newMiddle.isNotEmpty) return null;
  final removed = oldText.substring(prefix, oldText.length - suffix).trim();
  if (removed.isEmpty) return null;
  return removed;
}
