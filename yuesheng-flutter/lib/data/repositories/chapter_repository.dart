// ─────────────────────────────────────────────────────────────
// ChapterRepository — 章节 DAO
// 复刻 yuesheng-android/src/db/dao/basic-dao.ts 的 chapters 部分
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';
import '../database/database.dart';
import '../database/utils.dart';

class ChapterRepository {
  final AppDatabase _db;
  ChapterRepository(this._db);

  /// 创建章节，返回 id
  /// 复刻 createChapter(manuscriptId, title?, content?, index?)
  /// 批次89-2：volumeId 可空——新建章节直接落入指定卷（null = 未分卷）
  Future<String> createChapter(
    String manuscriptId, {
    String? title,
    String? content,
    int? sortOrder,
    String? volumeId,
  }) async {
    final id = generateUuid();
    final now = nowSec();
    // 如果没指定 sortOrder，取 MAX(sort_order)+1
    int order = sortOrder ?? 0;
    if (sortOrder == null) {
      final maxOrder =
          await (_db.selectOnly(_db.chapters)
                ..addColumns([_db.chapters.sortOrder.max()])
                ..where(_db.chapters.manuscriptId.equals(manuscriptId)))
              .getSingleOrNull();
      order = (maxOrder?.read(_db.chapters.sortOrder.max()) ?? -1) + 1;
    }

    await _db
        .into(_db.chapters)
        .insert(
          ChaptersCompanion.insert(
            id: id,
            manuscriptId: manuscriptId,
            title: Value(title ?? ''),
            content: Value(content ?? ''),
            wordCount: Value(content?.length ?? 0),
            sortOrder: Value(order),
            status: const Value('draft'),
            volumeId: Value(volumeId),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  /// 批量创建章节（事务内追加，sort_order 从 MAX+1 递增）
  /// 复刻 createChaptersBatch(manuscriptId, chapters)
  Future<int> createChaptersBatch(
    String manuscriptId,
    List<({String title, String content})> chapters,
  ) async {
    if (chapters.isEmpty) return 0;

    return _db.transaction(() async {
      // 取当前最大 sort_order
      final maxOrder =
          await (_db.selectOnly(_db.chapters)
                ..addColumns([_db.chapters.sortOrder.max()])
                ..where(_db.chapters.manuscriptId.equals(manuscriptId)))
              .getSingleOrNull();
      int order = (maxOrder?.read(_db.chapters.sortOrder.max()) ?? -1) + 1;
      final now = nowSec();

      for (final ch in chapters) {
        await _db
            .into(_db.chapters)
            .insert(
              ChaptersCompanion.insert(
                id: generateUuid(),
                manuscriptId: manuscriptId,
                title: Value(ch.title),
                content: Value(ch.content),
                wordCount: Value(ch.content.length),
                sortOrder: Value(order),
                status: const Value('draft'),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        order++;
      }
      return chapters.length;
    });
  }

  /// 获取单条章节
  /// 复刻 getChapter(chapterId)
  Future<Chapter?> getChapter(String chapterId) async {
    return (_db.select(
      _db.chapters,
    )..where((t) => t.id.equals(chapterId))).getSingleOrNull();
  }

  /// 列出稿件下所有章节（按 sort_order 排序）
  /// 复刻 listChapters(manuscriptId)
  /// 批次94-2：过滤回收站软删章节（status != 'archived'），回收站章节走
  /// listArchivedChapters 单独查询——软删对用户透明，统计/搜索/引用不混入。
  Future<List<Chapter>> listChapters(String manuscriptId) async {
    return (_db.select(_db.chapters)
          ..where(
            (t) =>
                t.manuscriptId.equals(manuscriptId) &
                t.status.isNotValue('archived'),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
  }

  /// 列出回收站中的章节（按 updated_at 倒序，批次94-2）
  Future<List<Chapter>> listArchivedChapters(String manuscriptId) async {
    return (_db.select(_db.chapters)
          ..where(
            (t) =>
                t.manuscriptId.equals(manuscriptId) &
                t.status.equals('archived'),
          )
          ..orderBy([
            (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// 软删章节 → 回收站（status='archived'，批次94-2）
  Future<void> softDeleteChapter(String chapterId) async {
    await (_db.update(
      _db.chapters,
    )..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(
        status: const Value('archived'),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 从回收站恢复章节（status → 'draft'，批次94-2）
  Future<void> restoreChapter(String chapterId) async {
    await (_db.update(
      _db.chapters,
    )..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(
        status: const Value('draft'),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 永久删除章节（回收站「彻底删除」，复用物理删除事务，批次94-2）
  Future<void> purgeChapter(String chapterId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.chapters,
      )..where((t) => t.id.equals(chapterId))).go();
      await (_db.delete(_db.sessionReferences)..where(
            (t) => t.refType.equals('chapter') & t.refId.equals(chapterId),
          ))
          .go();
    });
  }

  /// 保存章节内容（同步更新 word_count + updated_at）
  /// 复刻 saveChapterContent(chapterId, content)
  Future<void> saveChapterContent(String chapterId, String content) async {
    await (_db.update(
      _db.chapters,
    )..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(
        content: Value(content),
        wordCount: Value(content.length),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 更新章节标题
  /// 复刻 updateChapterTitle(chapterId, title)
  Future<void> updateChapterTitle(String chapterId, String title) async {
    await (_db.update(
      _db.chapters,
    )..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(title: Value(title), updatedAt: Value(nowSec())),
    );
  }

  /// 更新章节的最后诊断时间
  /// 复刻 updateChapterDiagnosedAt(chapterId)
  Future<void> updateChapterDiagnosedAt(String chapterId) async {
    await (_db.update(
      _db.chapters,
    )..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(
        lastDiagnosedAt: Value(nowSec()),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 采纳内容到章节（旧内容备份到 previous_content）
  /// 复刻 adoptContentToChapter(chapterId, newContent)
  Future<void> adoptContentToChapter(
    String chapterId,
    String newContent,
  ) async {
    final chapter = await getChapter(chapterId);
    if (chapter == null) return;

    await (_db.update(
      _db.chapters,
    )..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(
        previousContent: Value(chapter.content),
        content: Value(newContent),
        wordCount: Value(newContent.length),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 撤销上次采纳：将 previous_content 恢复为 content，并清空 previous_content
  /// 若 chapter 不存在或 previous_content 为 null，则不做任何操作。
  Future<void> undoLastAdoption(String chapterId) async {
    final chapter = await getChapter(chapterId);
    if (chapter == null || chapter.previousContent == null) return;

    final restored = chapter.previousContent!;
    await (_db.update(
      _db.chapters,
    )..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(
        content: Value(restored),
        previousContent: const Value(null),
        wordCount: Value(restored.length),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 按 sort_order 获取章节（解析 @W001/C003 语法用）
  /// 复刻 getChapterByOrder(manuscriptId, order)
  Future<Chapter?> getChapterByOrder(String manuscriptId, int order) async {
    return (_db.select(_db.chapters)
          ..where(
            (t) =>
                t.manuscriptId.equals(manuscriptId) & t.sortOrder.equals(order),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// 删除章节（批次 34，Flutter 新增能力，RN 无此功能）
  /// 事务内：
  ///   ① 物理删除章节（sessions.chapter_id 冗余缓存由外键 ON DELETE SET NULL 自动清空）
  ///   ② 清理 session_reference 中对该章节的悬空引用（ref_id 为软引用无外键约束）
  /// 历史记录（messages/diagnosis 的 target_ref）为软引用，保守保留不误删。
  Future<void> deleteChapter(String chapterId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.chapters,
      )..where((t) => t.id.equals(chapterId))).go();
      await (_db.delete(_db.sessionReferences)..where(
            (t) => t.refType.equals('chapter') & t.refId.equals(chapterId),
          ))
          .go();
    });
  }

  /// 交换两章 sort_order（批次96-1：卷内上移/下移）
  /// 事务内读取双方当前 sort_order 后互换，保证同卷相邻章节顺序翻转。
  /// 注意：sort_order 为全局整型，同卷章节在分组排序时仅按卷内比较，
  /// 交换后同卷内相对顺序即翻转（全局值可能不连续，但卷内排序正确）。
  Future<void> swapChapterSortOrder(String aId, String bId) async {
    await _db.transaction(() async {
      final a = await getChapter(aId);
      final b = await getChapter(bId);
      if (a == null || b == null) return;
      final now = nowSec();
      await (_db.update(_db.chapters)..where((t) => t.id.equals(aId))).write(
        ChaptersCompanion(
          sortOrder: Value(b.sortOrder),
          updatedAt: Value(now),
        ),
      );
      await (_db.update(_db.chapters)..where((t) => t.id.equals(bId))).write(
        ChaptersCompanion(
          sortOrder: Value(a.sortOrder),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// 更新章节 sort_order（批次96-1：跨卷移动时置入目标卷末位用）
  /// volumeId 由 VolumeRepository.setChapterVolume 负责，本方法仅改顺序。
  Future<void> updateChapterSortOrder(String chapterId, int sortOrder) async {
    await (_db.update(_db.chapters)..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(
        sortOrder: Value(sortOrder),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 批量统计多个作品的章节数 + 总字数。
  /// 单条 `WHERE manuscript_id IN (...)` 查询替代书架逐卡片 [listChapters] 的 N+1 查询（B27 修复）；
  /// 聚合在 Dart 侧完成，避免 drift 聚合表达式类型约束，且章节总量可控。
  Future<Map<String, ChapterStat>> statsForManuscripts(
    List<String> manuscriptIds,
  ) async {
    if (manuscriptIds.isEmpty) return const {};
    final chapters = await (_db.select(_db.chapters)
          ..where(
            (t) =>
                t.manuscriptId.isIn(manuscriptIds) &
                t.status.isNotValue('archived'),
          ))
        .get();
    final result = <String, ChapterStat>{};
    for (final c in chapters) {
      final prev = result[c.manuscriptId] ??
          const ChapterStat(chapterCount: 0, totalWords: 0);
      result[c.manuscriptId] = ChapterStat(
        chapterCount: prev.chapterCount + 1,
        totalWords: prev.totalWords + c.wordCount,
      );
    }
    return result;
  }
}

/// 作品章节统计（章节数 + 总字数，书架卡片信息加厚用；B27 批量查询返回值）
class ChapterStat {
  final int chapterCount;
  final int totalWords;
  const ChapterStat({required this.chapterCount, required this.totalWords});
}
