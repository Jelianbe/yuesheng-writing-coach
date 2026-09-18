// ─────────────────────────────────────────────────────────────
// chapter_number — 章号展示口径的**唯一实现点**
//
// 裁定见 `docs/ADR-C95-chapter-number-convention.md`。三条口径缺一会出错数字：
//
//   1. `chapters.sort_order` 是 **0 基内部身份/排序键**，**不是**展示号。它会因
//      删除（`chapter_repository.dart:177/221`，**不重编号**）、交换（`:348`）、
//      跨卷移动（`:368`）而不连续、不单调、不始于 0。
//   2. 展示号（`第N章` 的 N）**唯一**取自「该章在作品当前章节列表中的序位 + 1」。
//      列表 = `ChapterRepository.listChapters`（排除回收站、按 sort_order 升序），
//      与 UI 平铺顺序（`utils/volume_group.dart` 的 `buildChapterSections`）一致。
//   3. 因此 **`sortOrder + 1` 不等价**，**禁止**用作兜底公式 —— 只在「无删除且无重排」
//      时才偶然相等。ADR §3 列了三个**代码可达**的反例。
//
// ★ 已删章的引用：解析**失败**（返回 null）⇒ 调用方应**隐藏**章标，
//   不得编造一个数（ADR 裁定 2）。
//
// ★ 尚未覆盖（另批，ADR §4 裁定 4 / §5）：`first_seen_chapter`、
//   `assertion.chapter`（AI 自报，**与 sort_order 不同基**）、
//   `EventFact.chapter`、`SubplotFact.*Chapter` —— 这些字段**混装两种基号**，
//   在展示层**无法区分**，必须先改写入语义，不能在此顺手转换。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';

/// 由「已按 `sort_order` 升序的章节列表」构建 `sortOrder → 展示章号(1 基)`。
///
/// 入参列表须**已升序**（`ChapterRepository.listChapters` 保证）。同序重复时取
/// 首次出现的序位 —— 正常不出现（`createChapter` 取 `MAX+1`），仅作防御。
Map<int, int> buildChapterNoMap(List<Chapter> sortedChapters) {
  final map = <int, int>{};
  for (var i = 0; i < sortedChapters.length; i++) {
    map.putIfAbsent(sortedChapters[i].sortOrder, () => i + 1);
  }
  return map;
}

/// 解析展示章号。
///
/// [sortOrder] 为 null、或该章已不在列表中（已删 / 在回收站 / 越界）→ 返回 null。
/// **调用方不得用 `sortOrder + 1` 兜底**（见文件头口径 3）。
int? displayChapterNo(Map<int, int> chapterNoMap, int? sortOrder) {
  if (sortOrder == null) return null;
  return chapterNoMap[sortOrder];
}

/// 「第N章」标签文案；解析失败返回 **null**（调用方应隐藏标签，而非编造）。
String? chapterLabel(Map<int, int> chapterNoMap, int? sortOrder) {
  final no = displayChapterNo(chapterNoMap, sortOrder);
  return no == null ? null : '第$no章';
}
