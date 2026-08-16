// ─────────────────────────────────────────────────────────────
// work_import_service — 作品导入链路服务
// 真源：yuesheng-android/src/components/reference/WorkImportModal.tsx
//
// 职责（对应 RN handlePickFile → handleCreateWork 流程）：
//   1. importFromFile：选文件 → 读内容 → 解析 → 入库
//   2. importFromText：粘贴文本 → 解析 → 入库
//   3. importWork：事务内建稿件 + 逐章建章节 + 建主引用
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../data/repositories/reference_repository.dart';
import 'file_parser.dart';

/// 导入结果（对齐 RN onUploadComplete 的 meta 参数）
class WorkImportResult {
  final String title;
  final String manuscriptId;
  final String firstChapterId;
  final int chapterCount;
  final int totalWords;

  const WorkImportResult({
    required this.title,
    required this.manuscriptId,
    required this.firstChapterId,
    required this.chapterCount,
    required this.totalWords,
  });
}

/// 作品导入服务：把本地文件 / 粘贴文本解析成稿件入库，并挂到会话引用
class WorkImportService {
  final AppDatabase _db;
  final ManuscriptRepository _manuscriptRepo;
  final ChapterRepository _chapterRepo;
  final ReferenceRepository _referenceRepo;

  WorkImportService(
    this._db,
    this._manuscriptRepo,
    this._chapterRepo,
    this._referenceRepo,
  );

  /// 从本地文件导入（对齐 RN handlePickFile）。
  /// 用户取消选择返回 null；读取/解析/入库异常向上抛，由调用方提示。
  Future<WorkImportResult?> importFromFile({required String sessionId}) async {
    final picked = await pickDocument();
    if (picked == null) return null;

    final content = await readFileContent(picked.path);
    final parsed = parseDocument(content, picked.name);
    return importWork(sessionId: sessionId, parsed: parsed);
  }

  /// 从粘贴文本导入（对齐 RN handlePasteConfirm）
  Future<WorkImportResult> importFromText({
    required String sessionId,
    required String text,
    String name = '粘贴文本',
  }) async {
    final parsed = parseDocument(text, name);
    return importWork(sessionId: sessionId, parsed: parsed);
  }

  /// 从本地文件导入书籍（批次 35：书架新建场景，无会话上下文，不建引用）
  /// 用户取消选择返回 null；读取/解析/入库异常向上抛，由调用方提示。
  Future<WorkImportResult?> importBookFromFile() async {
    final picked = await pickDocument();
    if (picked == null) return null;
    final content = await readFileContent(picked.path);
    final parsed = parseDocument(content, picked.name);
    return importWork(sessionId: null, parsed: parsed);
  }

  /// 核心：事务内建稿件 + 逐章建章节（对齐 RN handleCreateWork）
  /// sessionId 非空时设第一章为主引用（对话页导入）；null（书架导入）不建引用。
  /// 任一环节失败整体回滚，不留半成品稿件。
  Future<WorkImportResult> importWork({
    String? sessionId,
    required ParsedFile parsed,
  }) async {
    if (parsed.chapters.isEmpty) {
      throw StateError('未识别到有效章节内容');
    }

    return _db.transaction(() async {
      final manuscriptId = await _manuscriptRepo.createManuscript(
        title: parsed.title,
        description: '从文件导入的作品（${parsed.chapters.length}章）',
        genre: parsed.genre,
      );

      var firstChapterId = '';
      for (var i = 0; i < parsed.chapters.length; i++) {
        final ch = parsed.chapters[i];
        final chapterId = await _chapterRepo.createChapter(
          manuscriptId,
          title: ch.title,
          content: ch.content,
          sortOrder: i + 1,
        );
        if (i == 0) firstChapterId = chapterId;
      }

      if (firstChapterId.isNotEmpty && sessionId != null) {
        await _referenceRepo.addReference(
          sessionId,
          'chapter',
          firstChapterId,
          isPrimary: true,
        );
      }

      final totalWords = parsed.chapters.fold<int>(
        0,
        (sum, ch) => sum + ch.content.length,
      );
      return WorkImportResult(
        title: parsed.title,
        manuscriptId: manuscriptId,
        firstChapterId: firstChapterId,
        chapterCount: parsed.chapters.length,
        totalWords: totalWords,
      );
    });
  }
}
