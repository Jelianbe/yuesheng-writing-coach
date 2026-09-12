// ─────────────────────────────────────────────────────────────
// manuscript_scope — 作品级会话范围（共享查询）
//
// 抽出动机（批次 A / 书籍级成长叙事）：
//   「与某作品相关的会话集合」这一语义原本私有在 SessionRepository
//   （详情页「相关对话」Tab 的数据源）。书籍级诊断聚合
//   （DiagnosisRepository）同样需要它——若不抽出而各自实现一遍，就会出现
//   「相关对话 Tab 显示 3 条、成长统计只算 1 条」的同语义双实现，
//   即 syndrome_recurrence.dart 抽出时要消除的同一类问题。
//
// 语义（与抽出前 listRelatedSessions 的命中规则逐字一致，取并集去重）：
//   1. session_reference 引用本书（refType=manuscript & refId=bookId）
//   2. session_reference 引用本书任意章节（refType=chapter & refId ∈ 本书章节）
//   3. sessions.manuscript_id 冗余缓存 == bookId
//      （getOrCreateSessionForManuscript/Chapter 写入）
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';

/// 汇总与作品 [manuscriptId] 相关的全部会话 id（三条来源取并集）。
///
/// 无相关会话时返回空集（不抛异常）——调用方据此短路返回空列表。
Future<Set<String>> collectManuscriptSessionIds(
  AppDatabase db,
  String manuscriptId,
) async {
  final chapterIds = await chapterIdsOf(db, manuscriptId);
  final hitIds = await _referencedSessionIds(db, manuscriptId, chapterIds);
  hitIds.addAll(await _cachedSessionIds(db, manuscriptId));
  return hitIds;
}

/// 本书全部章节 id 集合（R-019：由 collectManuscriptSessionIds 抽出）。
Future<Set<String>> chapterIdsOf(AppDatabase db, String manuscriptId) async {
  final chapters = await (db.select(
    db.chapters,
  )..where((t) => t.manuscriptId.equals(manuscriptId))).get();
  return chapters.map((c) => c.id).toSet();
}

/// session_reference 命中：manuscript 直引 + chapter 归属本书。
Future<Set<String>> _referencedSessionIds(
  AppDatabase db,
  String manuscriptId,
  Set<String> chapterIds,
) async {
  final hitIds = <String>{};
  final allRefs = await db.select(db.sessionReferences).get();
  for (final ref in allRefs) {
    if (ref.refType == 'manuscript' && ref.refId == manuscriptId) {
      hitIds.add(ref.sessionId);
    }
    if (ref.refType == 'chapter' && chapterIds.contains(ref.refId)) {
      hitIds.add(ref.sessionId);
    }
  }
  return hitIds;
}

/// sessions.manuscript_id 冗余缓存兜底。
Future<Set<String>> _cachedSessionIds(
  AppDatabase db,
  String manuscriptId,
) async {
  final cached = await (db.select(
    db.sessions,
  )..where((t) => t.manuscriptId.equals(manuscriptId))).get();
  return cached.map((s) => s.id).toSet();
}
