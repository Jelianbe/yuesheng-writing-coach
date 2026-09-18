// ─────────────────────────────────────────────────────────────
// 章节级 app_state 键（**共享叶子模块**）
//
// 为什么单独一个文件：
//   这些键的**写侧**分散在两个模块 ——
//     · `app_state_repository.dart` 写 `chapter_draft` / `chapter_versions`
//     · `writing_providers.dart` 写 `chapter_goal`
//   而**清侧**在 `chapter_repository.dart`（删章时一并清理）。
//   若清侧各自写键名**字面量**，将来新增一个「以章节 id 为后缀」的键时会
//   **静默漏清** ⇒ 孤儿行永久残留在 `app_state` 表里。
//   这正是已登记在案的存量缺陷 **B25**：
//     出处 `yuesheng-flutter/docs/verify-B-series-prompt-audit-2026-08-18.md:16`
//         与 `yuesheng-flutter/docs/内容层修正-执行提示词包.md:189`
//         （「章节删除清理 chapter_draft/chapter_versions KV」）。
//   ⇒ 本模块**不 import 任何项目内文件**，三侧都依赖它，图上只多三条叶子边。
//
// ★ 新增任何「以章节 id 为后缀」的键，必须同时登记到 [chapterScopedKeys]，
//   否则删章时会漏清 ⇒ 变成孤儿行。
// ★ N3 阶段 2（存储迁出：快照改为 `<doc>/versions/<id>/` 文件）若落地，
//   `chapter_versions_index:<id>` 必须登记进本清单。
//   （现在**不要**加：该键目前无人写入。）
// ─────────────────────────────────────────────────────────────

/// 章节草稿键（写入方：`AppStateRepository.saveChapterDraft`）
String chapterDraftKey(String chapterId) => 'chapter_draft:$chapterId';

/// 章节版本快照键（写入方：`AppStateRepository.addChapterVersion`）
String chapterVersionsKey(String chapterId) => 'chapter_versions:$chapterId';

/// 单章写作目标键（写入方：`WritingStore.setGoalWords`）
String chapterGoalKey(String chapterId) => 'chapter_goal:$chapterId';

/// 删除章节时**必须**一并清除的全部 app_state 键。
/// ★ 新增任何「以章节 id 为后缀」的键，必须同时登记到这里，否则会变成孤儿行。
List<String> chapterScopedKeys(String chapterId) => <String>[
  chapterDraftKey(chapterId),
  chapterVersionsKey(chapterId),
  chapterGoalKey(chapterId),
];
