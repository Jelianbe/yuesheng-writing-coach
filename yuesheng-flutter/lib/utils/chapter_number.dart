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
// ★ 覆盖范围（2026-09-18 `N12-F3a` 更新；取证见 `.ai/reports/2026-09-18-N12-F3-侦察.md §3`）：
//   ✅ `outline_impression.source_chapter_no` —— `N12-F1`
//   ✅ `character_fact.first_seen_chapter` —— `N12-F3a`；同时用 [sortOrderAtPosition]
//      把**用户手填的序位**在写入前归一到身份 ⇒ 该列此后**单语义 = 身份**。
//   ❌ `assertion.chapter` / `event_fact.chapter` / `subplot_fact.*_chapter` ——
//      实测是**第三个语义**：AI 抄的是**用户自撰的标称号**（章标题里写的号），
//      既不是身份也不是序位（报告 §1 决定性取证：全稿 1 章、标题「第二章」、正文
//      零处章号字样 ⇒ AI 报 2 只能来自标题）。**且这些列另有用户手工输入框** ⇒
//      在展示层**无法分辨**，必须先由写入侧**另存身份**。**不得**在此顺手转换（`N12-F3b`）。
//   ❌ `world_fact.first_seen_chapter` —— 实测**无机器写入方**（只有用户手填路径），
//      与 `character_fact` **同名不同基** ⇒ **不得**套用本文件任何函数（报告 §3.1）。
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

/// 展示章号（1 基**序位**）→ 该章的 `sortOrder`（**身份键**）；序位不存在返回 null。
///
/// 用途是**写侧**：用户能看到的、能填的只有「第几章」（序位），而库里该列存的是
/// 身份 —— 写入前必须归一，否则用户填「3」会被将来读成「`sortOrder == 3` 的那一章」
/// （两者只在无删除无重排的稿上偶然相等）。
///
/// 反查**必须**与 [buildChapterNoMap] 的去重规则一致（同序重复取首次出现的序位），
/// 故这里按**映射值**反查而非按列表下标取值：这样
/// `displayChapterNo(map, sortOrderAtPosition(map, p)) == p` 恒成立 ——
/// 正向与反向不可能分叉。
int? sortOrderAtPosition(Map<int, int> chapterNoMap, int position) {
  if (position < 1) return null;
  for (final entry in chapterNoMap.entries) {
    if (entry.value == position) return entry.key;
  }
  return null;
}
