// ─────────────────────────────────────────────────────────────
// ReferenceRepository — 会话引用 DAO + 附属文件 DAO
// 复刻 yuesheng-android/src/db/dao/reference-dao.ts + file-dao.ts
//
// 已实现：
//   读取：listReferencesOfSession / getAttachedFile / listAttachedFiles
//         listAttachedFilesByRole / getFileByOrder
//         listSessionsReferencing / getPrimaryReference
//   写入：createAttachedFile / updateAttachedFile / deleteAttachedFile
//         addReference / removeReference / setPrimaryReference
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';

/// 引用项（UNION ALL 查询结果）
class ReferencedItem {
  final String refId;
  final String refType; // 'manuscript' | 'chapter' | 'file'
  final int isPrimary;
  final String title;
  final String? manuscriptId;

  /// 批次5（5.5）：选段范围 JSON（如 {"start":100,"end":320}），chapter 引用专用
  final String? excerptRange;

  const ReferencedItem({
    required this.refId,
    required this.refType,
    required this.isPrimary,
    required this.title,
    this.manuscriptId,
    this.excerptRange,
  });
}

/// 附加文件（file-dao.getAttachedFile 等价物）
class AttachedFileRow {
  final String id;
  final String bookId;
  final String fileName;
  final String fileRole;
  final String mimeType;
  final String content;
  final int byteSize;

  const AttachedFileRow({
    required this.id,
    required this.bookId,
    required this.fileName,
    required this.fileRole,
    required this.mimeType,
    required this.content,
    required this.byteSize,
  });
}

class ReferenceRepository {
  final AppDatabase _db;

  ReferenceRepository(this._db);

  /// 列出会话的所有引用（UNION ALL manuscripts/chapters/attached_files）
  /// 复刻 reference-dao.ts listReferencesOfSession
  Future<List<ReferencedItem>> listReferencesOfSession(String sessionId) async {
    // 三段 UNION：manuscripts / chapters / attached_files
    // ORDER BY is_primary DESC
    final sql = '''
      SELECT sr.ref_id AS ref_id, sr.ref_type AS ref_type, sr.is_primary AS is_primary,
             sr.excerpt_range AS excerpt_range,
             m.title AS title, NULL AS manuscript_id
        FROM session_reference sr
        JOIN manuscripts m ON m.id = sr.ref_id
       WHERE sr.session_id = ? AND sr.ref_type = 'manuscript'
      UNION ALL
      SELECT sr.ref_id AS ref_id, sr.ref_type AS ref_type, sr.is_primary AS is_primary,
             sr.excerpt_range AS excerpt_range,
             c.title AS title, c.manuscript_id AS manuscript_id
        FROM session_reference sr
        JOIN chapters c ON c.id = sr.ref_id
       WHERE sr.session_id = ? AND sr.ref_type = 'chapter'
      UNION ALL
      SELECT sr.ref_id AS ref_id, sr.ref_type AS ref_type, sr.is_primary AS is_primary,
             sr.excerpt_range AS excerpt_range,
             f.file_name AS title, f.book_id AS manuscript_id
        FROM session_reference sr
        JOIN attached_files f ON f.id = sr.ref_id
       WHERE sr.session_id = ? AND sr.ref_type = 'file'
       ORDER BY is_primary DESC
    ''';
    final rows = await _db
        .customSelect(
          sql,
          variables: [
            Variable.withString(sessionId),
            Variable.withString(sessionId),
            Variable.withString(sessionId),
          ],
          readsFrom: {
            _db.sessionReferences,
            _db.manuscripts,
            _db.chapters,
            _db.attachedFiles,
          },
        )
        .get();

    return rows
        .map(
          (row) => ReferencedItem(
            refId: row.read<String>('ref_id'),
            refType: row.read<String>('ref_type'),
            isPrimary: row.read<int>('is_primary'),
            title: row.read<String>('title'),
            manuscriptId: row.readNullable<String>('manuscript_id'),
            excerptRange: row.readNullable<String>('excerpt_range'),
          ),
        )
        .toList();
  }

  /// 获取单个附加文件内容
  /// 复刻 file-dao.ts getAttachedFile
  Future<AttachedFileRow?> getAttachedFile(String fileId) async {
    final row = await (_db.select(
      _db.attachedFiles,
    )..where((t) => t.id.equals(fileId))).getSingleOrNull();
    if (row == null) return null;
    return AttachedFileRow(
      id: row.id,
      bookId: row.bookId,
      fileName: row.fileName,
      fileRole: row.fileRole,
      mimeType: row.mimeType,
      content: row.content,
      byteSize: row.byteSize,
    );
  }

  /// 按 id 集合批量取附属文件（A-3 遗留 N+1 消除：引用预加载用）
  /// 语义对齐 getAttachedFile：仅按 id 过滤，字段映射一致。空列表守卫避免 `IN ()` 非法 SQL。
  Future<List<AttachedFileRow>> getAttachedFilesByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const [];
    final rows = await (_db.select(_db.attachedFiles)
          ..where((t) => t.id.isIn(ids)))
        .get();
    return rows
        .map(
          (row) => AttachedFileRow(
            id: row.id,
            bookId: row.bookId,
            fileName: row.fileName,
            fileRole: row.fileRole,
            mimeType: row.mimeType,
            content: row.content,
            byteSize: row.byteSize,
          ),
        )
        .toList();
  }

  /// 列出书籍下所有附属文件
  /// 复刻 file-dao.ts listAttachedFiles
  Future<List<AttachedFileRow>> listAttachedFiles(String bookId) async {
    final rows =
        await (_db.select(_db.attachedFiles)
              ..where((t) => t.bookId.equals(bookId))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    return rows
        .map(
          (row) => AttachedFileRow(
            id: row.id,
            bookId: row.bookId,
            fileName: row.fileName,
            fileRole: row.fileRole,
            mimeType: row.mimeType,
            content: row.content,
            byteSize: row.byteSize,
          ),
        )
        .toList();
  }

  // ════════════ attached_files 写入 ════════════

  /// 创建附属文件，返回完整记录
  /// 复刻 file-dao.ts createAttachedFile
  Future<AttachedFileRow> createAttachedFile({
    required String bookId,
    required String fileName,
    String fileRole = 'general',
    String mimeType = 'text/plain',
    required String content,
    int? byteSize,
  }) async {
    final id = generateUuid();
    final now = nowSec();
    final size = byteSize ?? content.length;

    await _db
        .into(_db.attachedFiles)
        .insert(
          AttachedFilesCompanion.insert(
            id: id,
            bookId: bookId,
            fileName: Value(fileName),
            fileRole: Value(fileRole),
            mimeType: Value(mimeType),
            content: Value(content),
            byteSize: Value(size),
            sortOrder: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    return AttachedFileRow(
      id: id,
      bookId: bookId,
      fileName: fileName,
      fileRole: fileRole,
      mimeType: mimeType,
      content: content,
      byteSize: size,
    );
  }

  /// 更新附属文件（部分字段）
  /// 复刻 file-dao.ts updateAttachedFile
  /// 若更新 content 则同步刷新 byte_size
  Future<void> updateAttachedFile(
    String fileId, {
    String? fileName,
    String? fileRole,
    String? content,
  }) async {
    final hasChange = fileName != null || fileRole != null || content != null;
    if (!hasChange) return;

    await (_db.update(
      _db.attachedFiles,
    )..where((t) => t.id.equals(fileId))).write(
      AttachedFilesCompanion(
        fileName: fileName != null ? Value(fileName) : const Value.absent(),
        fileRole: fileRole != null ? Value(fileRole) : const Value.absent(),
        content: content != null ? Value(content) : const Value.absent(),
        byteSize: content != null
            ? Value(content.length)
            : const Value.absent(),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 删除附属文件（事务内同步清理 session_reference 孤儿行）
  /// 复刻 file-dao.ts deleteAttachedFile（T-003 修复）
  ///
  /// 注意：session_reference.ref_type CHECK 约束仅允许 manuscript|chapter，
  /// file 类型不会出现在 session_reference 中，此清理为防御性 no-op。
  Future<void> deleteAttachedFile(String fileId) async {
    await _db.transaction(() async {
      // 防御性清理（file 类型不在 session_reference，实际 no-op）
      await _db.customStatement(
        "DELETE FROM session_reference WHERE ref_type = 'file' AND ref_id = ?",
        [fileId],
      );
      await (_db.delete(
        _db.attachedFiles,
      )..where((t) => t.id.equals(fileId))).go();
    });
  }

  // ════════════ session_reference 写入 ════════════

  /// 给对话添加一条引用（幂等：UNIQUE(session_id, ref_type, ref_id)）
  /// 复刻 reference-dao.ts addReference
  ///
  /// refType 支持 'manuscript' | 'chapter' | 'file'（批次7 D2：v21 CHECK 已扩；
  /// file 仅作次引用，不可设主，setPrimaryReference 有 ArgumentError 防御）
  /// isPrimary=true 时切换主引用（清掉其它 primary + 同步 sessions 缓存）
  Future<String> addReference(
    String sessionId,
    String refType,
    String refId, {
    bool isPrimary = false,
    ({String chapterId, int startPara, int endPara})? excerptRange,
  }) async {
    final id = generateUuid();
    final now = nowSec();
    final excerpt = excerptRange != null
        ? '{"chapterId":"${excerptRange.chapterId}","startPara":${excerptRange.startPara},"endPara":${excerptRange.endPara}}'
        : null;

    await _db.transaction(() async {
      // 幂等插入：ON CONFLICT(session_id, ref_type, ref_id) 更新 excerpt_range
      // drift 的 insertOnConflictUpdate 默认用主键冲突，需用原生 SQL 指定 UNIQUE 约束
      await _db.customStatement(
        '''
        INSERT INTO session_reference (id, session_id, ref_type, ref_id, is_primary, excerpt_range, created_at)
        VALUES (?, ?, ?, ?, 0, ?, ?)
        ON CONFLICT(session_id, ref_type, ref_id) DO UPDATE SET excerpt_range = excluded.excerpt_range
        ''',
        [id, sessionId, refType, refId, excerpt, now],
      );
      if (isPrimary) {
        await _setPrimaryInTx(sessionId, refType, refId, now);
      }
    });
    return id;
  }

  /// 移除一条引用
  /// 复刻 reference-dao.ts removeReference
  ///
  /// 若删掉的是主引用，自动另选最早的一条作为新主引用；
  /// 若没有其它引用，清空 sessions.manuscript_id/chapter_id 缓存
  Future<void> removeReference(
    String sessionId,
    String refType,
    String refId,
  ) async {
    final now = nowSec();
    await _db.transaction(() async {
      // 查是否是主引用
      final wasPrimary =
          await (_db.selectOnly(_db.sessionReferences)
                ..addColumns([_db.sessionReferences.isPrimary])
                ..where(
                  _db.sessionReferences.sessionId.equals(sessionId) &
                      _db.sessionReferences.refType.equals(refType) &
                      _db.sessionReferences.refId.equals(refId),
                ))
              .getSingleOrNull();
      final wasPrimaryVal =
          wasPrimary?.read(_db.sessionReferences.isPrimary) ?? 0;

      // 删除引用
      await (_db.delete(_db.sessionReferences)..where(
            (t) =>
                t.sessionId.equals(sessionId) &
                t.refType.equals(refType) &
                t.refId.equals(refId),
          ))
          .go();

      // 若删的是主引用，另选最早的
      if (wasPrimaryVal == 1) {
        final next =
            await (_db.select(_db.sessionReferences)
                  ..where((t) => t.sessionId.equals(sessionId))
                  ..orderBy([(t) => OrderingTerm(expression: t.createdAt)])
                  ..limit(1))
                .getSingleOrNull();
        if (next != null) {
          await _setPrimaryInTx(sessionId, next.refType, next.refId, now);
        } else {
          // 没有其它引用，清空缓存
          await (_db.update(
            _db.sessions,
          )..where((t) => t.id.equals(sessionId))).write(
            SessionsCompanion(
              manuscriptId: const Value(null),
              chapterId: const Value(null),
              updatedAt: Value(now),
            ),
          );
        }
      }
    });
  }

  /// 设置主引用（file 类型禁止）
  /// 复刻 reference-dao.ts setPrimaryReference
  ///
  /// 事务内：清掉同 session 所有 is_primary → 设目标为 1 →
  /// 同步 sessions.manuscript_id/chapter_id 冗余缓存
  /// chapter 主引用时自动回填其所属 manuscript_id
  Future<void> setPrimaryReference(
    String sessionId,
    String refType,
    String refId,
  ) async {
    if (refType == 'file') {
      throw ArgumentError('素材文件不能设为主引用');
    }
    await _db.transaction(() async {
      await _setPrimaryInTx(sessionId, refType, refId, nowSec());
    });
  }

  /// 事务内：把某条置为主引用（清掉其它 primary），并同步 sessions 冗余缓存
  /// 复刻 reference-dao.ts setPrimaryInTx
  Future<void> _setPrimaryInTx(
    String sessionId,
    String refType,
    String refId,
    int now,
  ) async {
    // 清掉同 session 所有 is_primary
    await (_db.update(_db.sessionReferences)
          ..where((t) => t.sessionId.equals(sessionId)))
        .write(const SessionReferencesCompanion(isPrimary: Value(0)));

    // 设目标为 1
    await (_db.update(_db.sessionReferences)..where(
          (t) =>
              t.sessionId.equals(sessionId) &
              t.refType.equals(refType) &
              t.refId.equals(refId),
        ))
        .write(const SessionReferencesCompanion(isPrimary: Value(1)));

    // 同步冗余缓存：主引用是章节则连带回填其所属作品
    if (refType == 'chapter') {
      final ch =
          await (_db.selectOnly(_db.chapters)
                ..addColumns([_db.chapters.manuscriptId])
                ..where(_db.chapters.id.equals(refId)))
              .getSingleOrNull();
      final manuscriptId = ch?.read(_db.chapters.manuscriptId);
      await (_db.update(
        _db.sessions,
      )..where((t) => t.id.equals(sessionId))).write(
        SessionsCompanion(
          manuscriptId: manuscriptId != null
              ? Value(manuscriptId)
              : const Value(null),
          chapterId: Value(refId),
          updatedAt: Value(now),
        ),
      );
    } else {
      // manuscript 主引用
      await (_db.update(
        _db.sessions,
      )..where((t) => t.id.equals(sessionId))).write(
        SessionsCompanion(
          manuscriptId: Value(refId),
          chapterId: const Value(null),
          updatedAt: Value(now),
        ),
      );
    }
  }

  // ════════════ 辅助查询 ════════════

  /// 按角色过滤附属文件
  /// 复刻 file-dao.ts listAttachedFilesByRole
  Future<List<AttachedFileRow>> listAttachedFilesByRole(
    String bookId,
    String role,
  ) async {
    final rows =
        await (_db.select(_db.attachedFiles)
              ..where((t) => t.bookId.equals(bookId) & t.fileRole.equals(role))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    return rows
        .map(
          (row) => AttachedFileRow(
            id: row.id,
            bookId: row.bookId,
            fileName: row.fileName,
            fileRole: row.fileRole,
            mimeType: row.mimeType,
            content: row.content,
            byteSize: row.byteSize,
          ),
        )
        .toList();
  }

  /// 按 sort_order 查询素材文件（解析 @W001/F002 路径用）
  /// 复刻 file-dao.ts getFileByOrder
  Future<AttachedFileRow?> getFileByOrder(String bookId, int order) async {
    final row =
        await (_db.select(_db.attachedFiles)
              ..where(
                (t) => t.bookId.equals(bookId) & t.sortOrder.equals(order),
              )
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return AttachedFileRow(
      id: row.id,
      bookId: row.bookId,
      fileName: row.fileName,
      fileRole: row.fileRole,
      mimeType: row.mimeType,
      content: row.content,
      byteSize: row.byteSize,
    );
  }

  /// 反向查询：哪些对话引用了这个书/章（详情页反查）
  /// 复刻 reference-dao.ts listSessionsReferencing
  Future<List<ReferencingSession>> listSessionsReferencing(
    String refType,
    String refId,
  ) async {
    final sql = '''
      SELECT s.id AS session_id, s.title AS title, s.preview AS preview,
             sr.is_primary AS is_primary, s.updated_at AS updated_at
        FROM session_reference sr
        JOIN sessions s ON s.id = sr.session_id
       WHERE sr.ref_type = ? AND sr.ref_id = ?
       ORDER BY s.updated_at DESC
    ''';
    final rows = await _db
        .customSelect(
          sql,
          variables: [Variable.withString(refType), Variable.withString(refId)],
          readsFrom: {_db.sessionReferences, _db.sessions},
        )
        .get();

    return rows
        .map(
          (row) => ReferencingSession(
            sessionId: row.read<String>('session_id'),
            title: row.read<String>('title'),
            preview: row.read<String>('preview'),
            isPrimary: row.read<int>('is_primary'),
            updatedAt: row.read<int>('updated_at'),
          ),
        )
        .toList();
  }

  /// 获取会话主引用（诊断 target 默认值来源）
  /// 复刻 reference-dao.ts getPrimaryReference
  Future<({String refType, String refId})?> getPrimaryReference(
    String sessionId,
  ) async {
    final row =
        await (_db.selectOnly(_db.sessionReferences)
              ..addColumns([
                _db.sessionReferences.refType,
                _db.sessionReferences.refId,
              ])
              ..where(
                _db.sessionReferences.sessionId.equals(sessionId) &
                    _db.sessionReferences.isPrimary.equals(1),
              )
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return (
      refType: row.read(_db.sessionReferences.refType)!,
      refId: row.read(_db.sessionReferences.refId)!,
    );
  }
}

/// 反向查询结果：引用了某书/章的会话
/// 复刻 reference-dao.ts ReferencingSession
class ReferencingSession {
  final String sessionId;
  final String title;
  final String preview;
  final int isPrimary;
  final int updatedAt;

  const ReferencingSession({
    required this.sessionId,
    required this.title,
    required this.preview,
    required this.isPrimary,
    required this.updatedAt,
  });
}
