// ─────────────────────────────────────────────────────────────
// ChapterPosition — 被诊断章节在全书中的真实位次（T-20261025-06 件2）
//
// 从 `chat_diagnosis_controller.dart` 的私有 `_resolveChapterPosition` **逐字搬出**，
// 改为显式入参的纯服务函数：两条诊断入口（聊天页 / 写作教练面板）共用同一实现，
// 避免同一套「1 基索引」规则出现两份。旧私有方法在同批删除。
//
// **不直传 `Chapters.sortOrder`** —— 实测该列 0 基且 0/1 混用
// （`outputs/ev3.db` 中 `233efaae` 的「第一章 风起」存的是 `sort_order=1`），
// 直传会把第一章说成第二章。这里按 [ChapterRepository.listChapters] 的排序结果
// 取索引 ⇒ 与存储基值无关。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';

/// 被诊断章节在全书中的真实位次（1 基）与总章数；查不到 ⇒ null（不猜）。
Future<({int order, int total})?> resolveChapterPosition(
  ChapterRepository repo,
  Chapter chapter,
) async {
  try {
    final all = await repo.listChapters(chapter.manuscriptId);
    final idx = all.indexWhere((c) => c.id == chapter.id);
    if (idx < 0 || all.isEmpty) return null;
    return (order: idx + 1, total: all.length);
  } catch (_) {
    return null;
  }
}
