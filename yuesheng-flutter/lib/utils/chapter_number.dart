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
// ★ 覆盖范围（2026-09-18 `N12-F3a` / `N12-F3b` 更新；取证见
//   `.ai/reports/2026-09-18-N12-F3-侦察.md §3` 与 `...-N12-F3b-侦察.md §1`）：
//   ✅ `outline_impression.source_chapter_no` —— `N12-F1`
//   ✅ `character_fact.first_seen_chapter` —— `N12-F3a`；同时用 [sortOrderAtPosition]
//      把**用户手填的序位**在写入前归一到身份 ⇒ 该列此后**单语义 = 身份**。
//   ✅ `assertion.chapter` / `event_fact.chapter` / `subplot_fact.*_chapter` ——
//      `N12-F3b`：这三列实测是**第三个语义**（AI 抄用户自撰的**标称号**），
//      **一列多源、读时无法分辨** ⇒ 不在这列上做转换，而是由写入侧**另存身份**
//      （`chapterSortOrder` / `chapter_sort_order` / `*_sort_order`），
//      取值走 [resolveChapterIdentity]。展示侧切换留 phase 2（被存量读取口径阻塞）。
//   ❌ `world_fact.first_seen_chapter` —— 实测**无机器写入方**（只有用户手填路径），
//      与 `character_fact` **同名不同基** ⇒ **不得**套用本文件任何函数（报告 §3.1）。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';
import 'chapter_title.dart';

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

/// 该章的**三种编码**（身份 / 标称号 / 序位）——「当前章优先」判据的取值面。
///
/// 一个章在系统里同时有三个「都叫章号」的数（`ADR-C96 §1.2`）：身份
/// （`sortOrder`，0 基）、标称号（标题里写的号）、序位（1 基）。AI 报任一个
/// **都是按协议作答**，故判「AI 报的是不是当前章」必须三编码全试。
List<int> chapterEncodings(Chapter c, List<Chapter> sortedChapters) {
  final titleNo = chapterTitleNumber(c.title);
  final position = displayChapterNo(
    buildChapterNoMap(sortedChapters),
    c.sortOrder,
  );
  // 标称号 / 序位可能解析不出 ⇒ null-aware 元素**跳过**（不塞 null：列表中混入
  // null 会让下方 `.contains(aiNo)` 的语义变模糊，而 aiNo 恒非 null）。
  return [c.sortOrder, ?titleNo, ?position];
}

/// 按 **标称号 → 序位 → 身份** 的次序，把 [aiNo] 解析到一个真实章的 `sortOrder`；
/// 三编码都落到空处则返回 **null**（调用方决定兜底，本函数**不猜**）。
///
/// 编码序不可调换：默认标题下 `身份 = 序位 − 1`，若身份优先，AI 报的「序位 2」
/// 会被错锚到第 3 章（`ADR-C96 §2` 裁定 2 的显式论证）。
int? resolveByEncoding(int aiNo, List<Chapter> sortedChapters) {
  for (final c in sortedChapters) {
    if (chapterTitleNumber(c.title) == aiNo) return c.sortOrder;
  }
  final byPosition = sortOrderAtPosition(
    buildChapterNoMap(sortedChapters),
    aiNo,
  );
  if (byPosition != null) return byPosition;
  for (final c in sortedChapters) {
    if (c.sortOrder == aiNo) return c.sortOrder;
  }
  return null;
}

/// AI 自报章号 [aiNo] → 该事实所属章的**身份**（`sortOrder`）。永不返回 null。
///
/// 规则（`ADR-C96 §2` 裁定 2，四条按序判定）：
///   1. [aiNo] 为空 ⇒ 当前章（保留现行为，且与同行 `chapter_hash` 的假设一致）；
///   2. [aiNo] 命中**当前章**的任一编码 ⇒ 当前章；
///   3. 否则按 [resolveByEncoding] 解析到某个真实章 ⇒ 该章；
///   4. 都解析不到 ⇒ 当前章。
///
/// ★ 第 2 步（「当前章优先」）是本节的关键：干净稿上 AI 的号**总是指向当前章**，
///   故第 2 步总命中，编码阶梯**只在真正的跨章引用时才生效** —— 这消灭了
///   「AI 报错一个数、反被阶梯锚到**另一章**」的误锚（阶梯单独使用时的固有病）。
/// ★ 第 4 步**不落 NULL**：`subplot_closure_detector` 对无锚点支线直接跳过 ⇒ NULL 会让
///   **F11 检测覆盖率回退**；而 `currentSortOrder` 是确定成立的（那一章的正文正是
///   本次抽取来源，同行 `chapter_hash` 已如此断言）。
int resolveChapterIdentity(
  int? aiNo,
  List<Chapter> sortedChapters, {
  required int currentSortOrder,
}) {
  if (aiNo == null) return currentSortOrder;
  final cur = chapterAt(sortedChapters, currentSortOrder);
  if (cur != null && chapterEncodings(cur, sortedChapters).contains(aiNo)) {
    return currentSortOrder;
  }
  return resolveByEncoding(aiNo, sortedChapters) ?? currentSortOrder;
}

/// 从已升序列表里取某 `sortOrder` 对应的章；不在列表中（诊断途中被删 / 已归档）
/// ⇒ null。**不猜**一个不存在的章。
Chapter? chapterAt(List<Chapter> sortedChapters, int sortOrder) {
  for (final c in sortedChapters) {
    if (c.sortOrder == sortOrder) return c;
  }
  return null;
}
