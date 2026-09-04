// ─────────────────────────────────────────────────────────────
// SessionRepository — 会话 DAO + 消息 DAO
// 复刻 yuesheng-android/src/db/dao/basic-dao.ts 的 sessions + messages 部分
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../database/database.dart';
import '../database/utils.dart';
import '../../services/error_handler.dart';

class SessionRepository {
  final AppDatabase _db;
  SessionRepository(this._db);

  // ════════════ Sessions ════════════

  /// 创建空白会话，返回 id
  /// 复刻 createBlankSession(title?)
  ///
  /// ADR-C71 §3.3：beginnerLevel 是用户级学习属性（N 系课程进度坐标），
  /// 新会话继承全库最新非空值，否则零基础学员每段新对话都要重新赌
  /// LLM 块回填（N-1）。phase/subphase/attitudeLevel 维持会话级，不继承。
  Future<String> createBlankSession({String? title}) async {
    final id = generateUuid();
    final now = nowSec();
    final inheritedLevel = await _latestBeginnerLevel();
    await _db.transaction(() async {
      await _db
          .into(_db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: id,
              title: Value(title ?? '新建会话'),
              preview: const Value(''),
              diagnosisSummary: const Value('{}'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      // 同步创建 teaching_state 行（INSERT OR IGNORE，默认 P0_ENGAGE）
      await _db
          .into(_db.teachingState)
          .insertOnConflictUpdate(
            TeachingStateCompanion.insert(
              id: generateUuid(),
              sessionId: id,
              currentPhase: const Value('P0_ENGAGE'),
              // ADR-C71 §3.3：beginnerLevel 用户级继承
              beginnerLevel: inheritedLevel == null
                  ? const Value.absent()
                  : Value(inheritedLevel),
              updatedAt: Value(now),
            ),
          );
    });
    return id;
  }

  /// 全库最新非空 beginnerLevel（ADR-C71；无任何历史时返回 null）
  Future<String?> _latestBeginnerLevel() async {
    final row =
        await (_db.select(_db.teachingState)
              ..where((t) => t.beginnerLevel.isNotNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.updatedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();
    return row?.beginnerLevel;
  }

  /// 获取或创建稿件/章节关联会话
  /// 复刻 getOrCreateSessionForManuscript(manuscriptId, chapterId?)
  /// 逻辑：先查是否有 session.manuscript_id == manuscriptId，有则复用；否则新建 + 建主引用
  Future<String> getOrCreateSessionForManuscript(
    String manuscriptId, {
    String? chapterId,
  }) async {
    // 先查现有会话
    final existing =
        await (_db.select(_db.sessions)
              ..where((t) => t.manuscriptId.equals(manuscriptId))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.updatedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();

    if (existing != null) return existing.id;

    // 新建会话（建会话 + 建 teaching_state + 建冗余缓存 + 建引用，整体包事务，避免半完成态）
    final sessionId = await _db.transaction(() async {
      final sid = await createBlankSession(title: '新建会话');

      // 写入冗余缓存 + 主引用
      await (_db.update(_db.sessions)..where((t) => t.id.equals(sid))).write(
        SessionsCompanion(
          manuscriptId: Value(manuscriptId),
          chapterId: chapterId != null
              ? Value(chapterId)
              : const Value.absent(),
          updatedAt: Value(nowSec()),
        ),
      );

      // 建主引用（session_reference）
      await _db
          .into(_db.sessionReferences)
          .insertOnConflictUpdate(
            SessionReferencesCompanion.insert(
              id: generateUuid(),
              sessionId: sid,
              refType: 'manuscript',
              refId: manuscriptId,
              isPrimary: const Value(1),
              createdAt: Value(nowSec()),
            ),
          );
      if (chapterId != null) {
        await _db
            .into(_db.sessionReferences)
            .insertOnConflictUpdate(
              SessionReferencesCompanion.insert(
                id: generateUuid(),
                sessionId: sid,
                refType: 'chapter',
                refId: chapterId,
                isPrimary: const Value(1),
                createdAt: Value(nowSec()),
              ),
            );
      }

      return sid;
    });

    return sessionId;
  }

  /// 获取或创建章节级隔离会话
  /// 每个 chapter 拥有独立会话，诊断/对话互不污染
  /// 逻辑：先查 session.chapter_id == chapterId，有则复用；否则新建 + 建主引用
  Future<String> getOrCreateSessionForChapter(
    String manuscriptId,
    String chapterId,
  ) async {
    // 先查该章节的现有会话（按 chapter_id 精确匹配）
    final existing =
        await (_db.select(_db.sessions)
              ..where((t) => t.chapterId.equals(chapterId))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.updatedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();

    if (existing != null) return existing.id;

    // 新建会话（批次61：用章节标题命名「诊断·章节标题」，会话列表可辨识；
    // 标题为空回退「章节会话」；章节查询失败不影响会话创建）
    String chapterTitle = '';
    try {
      final chapter = await (_db.select(
        _db.chapters,
      )..where((t) => t.id.equals(chapterId))).getSingleOrNull();
      chapterTitle = chapter?.title ?? '';
    } catch (e, st) {
      // 降级行为保留：标题取不到 → 会话名回退「章节会话」，不影响会话创建。
      // 此前为空 catch，会话名异常时无从追溯，此处补可观测性。
      debugPrint('[SessionRepo] 章节标题查询失败，会话名回退: error=$e');
      ErrorHandler.instance.captureError(
        level: 'warn',
        category: 'database',
        message: '章节标题查询失败，会话名回退为「章节会话」',
        context: {'chapterId': chapterId, 'error': '$e'},
        stack: '$st',
      );
    }
    // 新建会话（建会话 + 建 teaching_state + 建冗余缓存 + 建引用，整体包事务，避免半完成态）
    final sessionId = await _db.transaction(() async {
      final sid = await createBlankSession(
        title: chapterTitle.trim().isEmpty ? '章节会话' : '诊断·$chapterTitle',
      );

      // 写入冗余缓存
      await (_db.update(_db.sessions)..where((t) => t.id.equals(sid))).write(
        SessionsCompanion(
          manuscriptId: Value(manuscriptId),
          chapterId: Value(chapterId),
          updatedAt: Value(nowSec()),
        ),
      );

      // 建主引用：chapter 为 primary（诊断目标）
      await _db
          .into(_db.sessionReferences)
          .insertOnConflictUpdate(
            SessionReferencesCompanion.insert(
              id: generateUuid(),
              sessionId: sid,
              refType: 'chapter',
              refId: chapterId,
              isPrimary: const Value(1),
              createdAt: Value(nowSec()),
            ),
          );
      // manuscript 作为次要引用（提供全局上下文）
      await _db
          .into(_db.sessionReferences)
          .insertOnConflictUpdate(
            SessionReferencesCompanion.insert(
              id: generateUuid(),
              sessionId: sid,
              refType: 'manuscript',
              refId: manuscriptId,
              isPrimary: const Value(0),
              createdAt: Value(nowSec()),
            ),
          );

      return sid;
    });

    return sessionId;
  }

  /// 列出所有会话（按 updated_at DESC）
  /// 复刻 listSessions()
  Future<List<SessionRow>> listSessions() async {
    return (_db.select(_db.sessions)..orderBy([
          (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        ]))
        .get();
  }

  /// 列出会话 + 教学阶段（LEFT JOIN teaching_state）
  /// 复刻 listSessionsWithPhase()
  Future<List<SessionWithPhase>> listSessionsWithPhase() async {
    final query =
        _db.select(_db.sessions).join([
          leftOuterJoin(
            _db.teachingState,
            _db.teachingState.sessionId.equalsExp(_db.sessions.id),
          ),
        ])..orderBy([
          OrderingTerm(
            expression: _db.sessions.updatedAt,
            mode: OrderingMode.desc,
          ),
        ]);

    final rows = await query.get();
    return rows.map((row) {
      final session = row.readTable(_db.sessions);
      final state = row.readTableOrNull(_db.teachingState);
      return SessionWithPhase(
        session: session,
        currentPhase: state?.currentPhase,
      );
    }).toList();
  }

  /// 列出与某作品相关的会话（详情页「相关对话」Tab 数据源）
  ///
  /// 命中规则（取并集，去重）：
  ///   1. session_reference 中引用本书（refType=manuscript & refId=bookId）
  ///   2. session_reference 中引用本书任意章节（refType=chapter & refId ∈ 本书章节）
  ///   3. sessions.manuscript_id 冗余缓存 == bookId（getOrCreateSessionForManuscript/Chapter 写入）
  ///
  /// 排序：按 sessions.updated_at 降序（活跃度 = 最后活动时间）
  Future<List<SessionWithPhase>> listRelatedSessions(
    String manuscriptId,
  ) async {
    final hitIds = await _collectRelatedSessionIds(manuscriptId);
    if (hitIds.isEmpty) return const [];
    return _querySessionsWithPhase(hitIds);
  }

  /// 汇总「与本书相关」的会话 id：章节直接归属 + session_reference 命中
  /// （manuscript 直引 / chapter 归属本书）+ manuscript_id 冗余缓存兜底。
  ///
  /// R-019：由 [listRelatedSessions] 抽出（57 → 6 行）。
  Future<Set<String>> _collectRelatedSessionIds(String manuscriptId) async {
    // 1. 本书章节 id 集合
    final chapters = await (_db.select(
      _db.chapters,
    )..where((t) => t.manuscriptId.equals(manuscriptId))).get();
    final chapterIds = chapters.map((c) => c.id).toSet();

    // 2. session_reference 命中
    final hitIds = <String>{};
    final allRefs = await _db.select(_db.sessionReferences).get();
    for (final ref in allRefs) {
      if (ref.refType == 'manuscript' && ref.refId == manuscriptId) {
        hitIds.add(ref.sessionId);
      }
      if (ref.refType == 'chapter' && chapterIds.contains(ref.refId)) {
        hitIds.add(ref.sessionId);
      }
    }

    // 3. sessions.manuscript_id 冗余缓存兜底
    final cached = await (_db.select(
      _db.sessions,
    )..where((t) => t.manuscriptId.equals(manuscriptId))).get();
    for (final s in cached) {
      hitIds.add(s.id);
    }
    return hitIds;
  }

  /// 按 [hitIds] 查会话并左连接教学阶段，按活跃度（updated_at 降序）返回。
  ///
  /// R-019：由 [listRelatedSessions] 抽出。
  Future<List<SessionWithPhase>> _querySessionsWithPhase(
    Set<String> hitIds,
  ) async {
    final query =
        _db.select(_db.sessions).join([
            leftOuterJoin(
              _db.teachingState,
              _db.teachingState.sessionId.equalsExp(_db.sessions.id),
            ),
          ])
          ..where(_db.sessions.id.isIn(hitIds))
          ..orderBy([
            OrderingTerm(
              expression: _db.sessions.updatedAt,
              mode: OrderingMode.desc,
            ),
          ]);

    final rows = await query.get();
    return rows.map((row) {
      final session = row.readTable(_db.sessions);
      final state = row.readTableOrNull(_db.teachingState);
      return SessionWithPhase(
        session: session,
        currentPhase: state?.currentPhase,
      );
    }).toList();
  }

  // ════════════ Messages ════════════

  /// 添加消息（事务：插消息 + 更新 sessions.preview/updated_at）
  /// 复刻 addMessage(sessionId, role, content, messageType?)
  /// 只有 messageType === 'chat' 才更新 preview
  /// [referencesJson]：本消息携带的 @ 引用快照（JSON 数组字符串，
  /// 批次71 @ 引用可视化——气泡底部展示引用徽章）
  Future<String> addMessage(
    String sessionId,
    String role,
    String content, {
    String messageType = 'chat',
    String? referencesJson,
  }) async {
    final id = generateUuid();
    final now = nowSec();

    return _db.transaction(() async {
      await _db
          .into(_db.messages)
          .insert(
            MessagesCompanion.insert(
              id: id,
              sessionId: sessionId,
              role: role,
              content: content,
              timestamp: Value(now),
              messageType: Value(messageType),
              referencesJson: Value(referencesJson),
            ),
          );

      // 只有 chat 类型才更新 preview（卡片类消息不污染列表预览）
      if (messageType == 'chat') {
        final preview = content.length > 50
            ? content.substring(0, 50)
            : content;
        await (_db.update(
          _db.sessions,
        )..where((t) => t.id.equals(sessionId))).write(
          SessionsCompanion(preview: Value(preview), updatedAt: Value(now)),
        );
      } else {
        await (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId)))
            .write(SessionsCompanion(updatedAt: Value(now)));
      }
      return id;
    });
  }

  /// 更新消息内容（quiz 答题状态内联持久化，按 messageId 关联）
  /// 仅重写 content 列；不更新 preview/sessions（卡片类消息不污染列表预览）。
  Future<void> updateMessageContent(String messageId, String content) async {
    await (_db.update(_db.messages)..where((t) => t.id.equals(messageId)))
        .write(MessagesCompanion(content: Value(content)));
  }

  /// 列出会话所有消息（按 timestamp ASC）
  /// 复刻 listMessages(sessionId)
  /// 注：RN 真源为 `ORDER BY timestamp, id`，但 id 为随机 UUID v4（无时间前缀），
  /// 同秒多条时 id 次级排序产生随机顺序，反而不如仅按 timestamp（SQLite 按插入行序
  /// 返回更可预期）。真实场景 user/assistant 消息跨秒（LLM 响应延迟），timestamp
  /// 排序已足够——保持 Flutter 原实现，不模仿 RN 的随机次级排序（批次 46 审计结论）。
  Future<List<Message>> listMessages(String sessionId) async {
    return (_db.select(_db.messages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm(expression: t.timestamp)]))
        .get();
  }

  /// 删除消息
  /// 复刻 deleteMessage(sessionId, messageId)
  Future<void> deleteMessage(String sessionId, String messageId) async {
    await (_db.delete(
          _db.messages,
        )..where((t) => t.sessionId.equals(sessionId) & t.id.equals(messageId)))
        .go();
  }

  /// 删除单个会话（批次73：会话可清理，对齐抽屉长按删除入口）
  ///
  /// 依赖外键 ON DELETE CASCADE（messages/diagnosis_results/teaching_state/
  /// active_problem/session_reference/teacher_suggestion/editor_observation
  /// 自动级联；sessions.manuscriptId/chapterId 为 SET NULL 自动置空）。
  /// 手动清理两类无级联数据：
  ///   - student_model：按 sessionId 存储，会话删除后该行成死数据；且其
  ///     session_id 列 NOT NULL + FK SET NULL 会违反约束，故显式删行
  ///   - app_state：无外键，清理 eval_round:/eval_report: 孤儿键
  ///     （对齐 deleteOrphanSessions 的批次5 5.4 处理）
  Future<void> deleteSession(String sessionId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.studentModels,
      )..where((t) => t.sessionId.equals(sessionId))).go();
      await (_db.delete(
        _db.appStates,
      )..where((t) => t.key.like('eval_report:$sessionId:%'))).go();
      await (_db.delete(
        _db.appStates,
      )..where((t) => t.key.equals('eval_round:$sessionId'))).go();
      await (_db.delete(
        _db.sessions,
      )..where((t) => t.id.equals(sessionId))).go();
    });
  }

  /// 清除缓存：删除没有任何消息的孤儿会话
  ///
  /// 复刻 RN settings.tsx handleClearCache 的 SQL：
  /// DELETE FROM chat_sessions WHERE id NOT IN (SELECT DISTINCT session_id FROM messages)
  /// 依赖外键 ON DELETE CASCADE（messages/diagnosis_results/session_reference 等
  /// 自动级联清理）。student_model 的 session_id 为 NOT NULL + FK SET NULL，
  /// 删除会话会触发 NOT NULL 违反，故事务内先显式删 studentModels（同 deleteSession）。
  /// 返回删除的会话数。
  /// 批次5（5.4）：会话删除事务内同步清理 app_state 孤儿 KV
  /// （eval_round:/eval_report: 前缀键，app_state 无外键不级联）。
  Future<int> deleteOrphanSessions() async {
    final sessions = await _db.select(_db.sessions).get();
    var deleted = 0;
    for (final s in sessions) {
      final msgCount = await (_db.select(
        _db.messages,
      )..where((t) => t.sessionId.equals(s.id))).get().then((l) => l.length);
      if (msgCount == 0) {
        await _db.transaction(() async {
          await (_db.delete(
            _db.studentModels,
          )..where((t) => t.sessionId.equals(s.id))).go();
          await (_db.delete(
            _db.sessions,
          )..where((t) => t.id.equals(s.id))).go();
          await (_db.delete(
            _db.appStates,
          )..where((t) => t.key.like('eval_report:${s.id}:%'))).go();
          await (_db.delete(
            _db.appStates,
          )..where((t) => t.key.equals('eval_round:${s.id}'))).go();
        });
        deleted++;
      }
    }
    return deleted;
  }
}

/// 会话 + 教学阶段联合查询结果
/// 复刻原项目 SessionWithPhase 类型
class SessionWithPhase {
  final SessionRow session;
  final String? currentPhase;
  SessionWithPhase({required this.session, this.currentPhase});
}
