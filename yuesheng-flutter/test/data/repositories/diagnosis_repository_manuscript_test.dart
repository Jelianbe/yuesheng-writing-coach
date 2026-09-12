// ─────────────────────────────────────────────────────────────
// 批次 A：书籍级诊断聚合读路径（三层成长叙事的中间层）
//
// 系统天然有三层成长叙事：章节级（这次谈什么）/ 书籍级（这本书学到
// 什么）/ 全库级（我是个怎样的写作者）。本批补的是**中间那层**——
// 此前书籍级只喂给详情页一个 Tab，没有任何聚合读路径。
//
// 本文件验证：
//   1. 单作品场景下书籍级与全库级数量一致（**双实现互证**：防书籍级
//      命中规则与 listRelatedSessions 分叉）
//   2. 多作品场景下书籍级正确隔离
//   3. 零会话 / 不存在作品 → 返回空且不抛异常
//   4. 会话范围取自共享并集查询（仅靠 session_reference 归属、无
//      manuscript_id 缓存的会话也必须被命中）
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';

void main() {
  late AppDatabase db;
  late DiagnosisRepository diagRepo;
  late SessionRepository sessionRepo;
  late ChapterRepository chapterRepo;
  late ManuscriptRepository manuscriptRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    diagRepo = DiagnosisRepository(db);
    sessionRepo = SessionRepository(db);
    chapterRepo = ChapterRepository(db);
    manuscriptRepo = ManuscriptRepository(db);
  });

  tearDown(() async => db.close());

  /// 在指定章节的会话上落一条诊断（走真实链路：章节会话 + commitDiagnosis）。
  Future<void> diagnoseChapter(
    String manuscriptId,
    String chapterId,
    String syndromeId, {
    String severity = 'L2',
  }) async {
    final sid = await sessionRepo.getOrCreateSessionForChapter(
      manuscriptId,
      chapterId,
    );
    await diagRepo.commitDiagnosis(
      DiagnosisInput(
        sessionId: sid,
        messageId: 'msg-$chapterId',
        syndromes: [
          {
            'syndrome_id': syndromeId,
            'name': '症候$syndromeId',
            'severity': severity,
          },
        ],
        suggestedActions: const [],
        confidence: 0.8,
        targetRefType: 'chapter',
        targetRefId: chapterId,
      ),
    );
  }

  group('书籍级诊断聚合（批次 A）', () {
    test('#1 单作品 3 章各一次诊断 → 书籍级 = 全库 = 3（双实现互证）', () async {
      final ms = await manuscriptRepo.createManuscript(title: '作品甲');
      for (final t in ['第一章', '第二章', '第三章']) {
        final c = await chapterRepo.createChapter(ms, title: t);
        await diagnoseChapter(ms, c, 'S001');
      }

      final scoped = await diagRepo.listDiagnosesForManuscript(ms);
      final global = await diagRepo.getAllDiagnosisRows();

      expect(scoped.length, 3, reason: '书籍级应命中本书 3 次诊断');
      expect(scoped.length, global.length, reason: '单作品场景下两路实现必须一致');
    });

    test('#2 第二本书的诊断不串入第一本（隔离）', () async {
      final msA = await manuscriptRepo.createManuscript(title: '作品甲');
      for (final t in ['第一章', '第二章', '第三章']) {
        final c = await chapterRepo.createChapter(msA, title: t);
        await diagnoseChapter(msA, c, 'S001');
      }
      final msB = await manuscriptRepo.createManuscript(title: '作品乙');
      final cB = await chapterRepo.createChapter(msB, title: '独章');
      await diagnoseChapter(msB, cB, 'S002');

      expect((await diagRepo.listDiagnosesForManuscript(msA)).length, 3);
      expect((await diagRepo.listDiagnosesForManuscript(msB)).length, 1);
      expect((await diagRepo.getAllDiagnosisRows()).length, 4);
    });

    test('#3 零会话作品 → 三个读路径均返回空且不抛异常', () async {
      final ms = await manuscriptRepo.createManuscript(title: '空作品');
      expect(await diagRepo.listDiagnosesForManuscript(ms), isEmpty);
      expect(await diagRepo.listActiveProblemsForManuscript(ms), isEmpty);
      expect(await diagRepo.getSyndromeRecurrencesForManuscript(ms), isEmpty);
    });

    test('#4 不存在的作品 id → 返回空且不抛异常', () async {
      expect(await diagRepo.listDiagnosesForManuscript('not-exist'), isEmpty);
      expect(
        await diagRepo.listActiveProblemsForManuscript('not-exist'),
        isEmpty,
      );
      expect(
        await diagRepo.getSyndromeRecurrencesForManuscript('not-exist'),
        isEmpty,
      );
    });

    test('#5 活跃问题按书籍聚合：不取到别书的严重度', () async {
      final msA = await manuscriptRepo.createManuscript(title: '作品甲');
      final cA = await chapterRepo.createChapter(msA, title: '甲1');
      await diagnoseChapter(msA, cA, 'S001', severity: 'L1');

      // 时间差 1 秒：created_at 精度到秒，否则「取最新」在 3.5 判据下不可判
      await Future<void>.delayed(const Duration(seconds: 1));

      final msB = await manuscriptRepo.createManuscript(title: '作品乙');
      final cB = await chapterRepo.createChapter(msB, title: '乙1');
      await diagnoseChapter(msB, cB, 'S001', severity: 'L3');

      final scopedA = await diagRepo.listActiveProblemsForManuscript(msA);
      expect(scopedA.length, 1);
      expect(scopedA.first.severity, 'L1', reason: '不得取到作品乙的 L3');

      final global = await diagRepo.listAllActiveProblems();
      expect(global.length, 1);
      expect(global.first.severity, 'L3', reason: '全库聚合应取最新严重度');
    });

    test('#6 复发聚合按书籍过滤（跨章节会话构成复发）', () async {
      final msA = await manuscriptRepo.createManuscript(title: '作品甲');
      final c1 = await chapterRepo.createChapter(msA, title: '甲1');
      await diagnoseChapter(msA, c1, 'S001');
      final sid1 = await sessionRepo.getOrCreateSessionForChapter(msA, c1);
      await diagRepo.resolveProblem(sid1, 'S001');

      await Future<void>.delayed(const Duration(seconds: 1));

      // 另一章的新会话再犯同症候 → 构成一次复发
      final c2 = await chapterRepo.createChapter(msA, title: '甲2');
      await diagnoseChapter(msA, c2, 'S001');

      final scoped = await diagRepo.getSyndromeRecurrencesForManuscript(msA);
      expect(scoped.length, 1);
      expect(scoped.first.occurrences, 2);
      expect(scoped.first.recurrences, 1, reason: '好转后再犯应计一次复发');

      final msB = await manuscriptRepo.createManuscript(title: '作品乙');
      expect(await diagRepo.getSyndromeRecurrencesForManuscript(msB), isEmpty);
    });

    test('#7 仅靠 session_reference 归属的会话也被命中（并集语义）', () async {
      // 造一个 manuscript_id 为空的「游离会话」，只靠章节引用归属本书——
      // 若改用 sessions.manuscript_id 单条件直查，此用例必然漏命中。
      final ms = await manuscriptRepo.createManuscript(title: '作品丙');
      final c = await chapterRepo.createChapter(ms, title: '丙1');
      final sid = await sessionRepo.createBlankSession(title: '游离会话');
      await db
          .into(db.sessionReferences)
          .insert(
            SessionReferencesCompanion.insert(
              id: 'ref-free-1',
              sessionId: sid,
              refType: 'chapter',
              refId: c,
              isPrimary: const Value(1),
            ),
          );
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-free',
          syndromes: const [
            {'syndrome_id': 'S007', 'name': '游离症候', 'severity': 'L2'},
          ],
          suggestedActions: const [],
          confidence: 0.7,
        ),
      );

      final scoped = await diagRepo.listDiagnosesForManuscript(ms);
      expect(scoped.length, 1, reason: '并集语义不得漏掉仅靠引用归属的会话');
    });
  });
}
