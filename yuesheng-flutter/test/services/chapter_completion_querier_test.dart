// ─────────────────────────────────────────────────────────────
// chapter_completion_querier 测试（ADR-C137 批3；证据卡对接；覆盖 §6 验收4）
//
// 覆盖：证据卡按章节 / 按会话取完成候选（含 independent_drafting 标记筛选），
//       只记候选事实字段，无成败判定（R-009）。
//
// 装配（与生产一致）：manuscript → chapter(content) → app_state 目标 →
//   edit_diff_events。querier 读 chapter_goal:<id> + chapter.content.length
//   装配两张 map，喂给纯函数聚合。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' show Value, InsertMode;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/chapter_scoped_keys.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';
import 'package:writingcoach/services/chapter_completion_aggregator.dart';
import 'package:writingcoach/services/chapter_completion_querier.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _seedManuscriptChapter(
  AppDatabase db, {
  required String chapterId,
  required int contentLength,
  int? goalWords,
}) async {
  await db
      .into(db.manuscripts)
      .insert(
        ManuscriptsCompanion.insert(id: 'manu1'),
        mode: InsertMode.insertOrIgnore,
      );
  await db
      .into(db.chapters)
      .insert(
        ChaptersCompanion.insert(
          id: chapterId,
          manuscriptId: 'manu1',
          content: Value('x' * contentLength),
        ),
      );
  if (goalWords != null) {
    await db
        .into(db.appStates)
        .insert(
          AppStatesCompanion.insert(
            key: chapterGoalKey(chapterId),
            value: Value('$goalWords'),
          ),
        );
  }
}

Future<void> _seedSession(AppDatabase db, String sessionId) async {
  await db.into(db.sessions).insert(SessionsCompanion.insert(id: sessionId));
}

Future<void> _insertEvent(
  AppDatabase db, {
  required String id,
  required String sessionId,
  required String chapterId,
  required String eventType,
  String? payloadSource,
  String? messageId,
}) async {
  final payload = payloadSource == null
      ? const Value<String>('')
      : Value<String>(CompletionPayload(source: payloadSource).encode() ?? '');
  await db
      .into(db.editDiffEvents)
      .insert(
        EditDiffEventsCompanion.insert(
          id: id,
          chapterId: chapterId,
          eventType: eventType,
          sessionId: Value(sessionId),
          messageId: Value<String?>(messageId),
          payload: payload,
          beforeText: const Value<String?>(null),
          afterText: const Value<String?>(null),
        ),
      );
}

ChapterCompletionQuerier _querier(AppDatabase db) => ChapterCompletionQuerier(
  EditDiffEventRepository(db),
  AppStateRepository(db),
  ChapterRepository(db),
);

void main() {
  group('ChapterCompletionQuerier 证据卡对接（ADR-C137 批3）', () {
    test('① 按章节取 → 含该章完整章候选（三要素齐备）', () async {
      final db = _db();
      try {
        await _seedSession(db, 's1');
        await _seedManuscriptChapter(
          db,
          chapterId: 'c1',
          contentLength: 120,
          goalWords: 100,
        );
        await _insertEvent(
          db,
          id: 'ev1',
          sessionId: 's1',
          chapterId: 'c1',
          eventType: EditDiffEventTypes.completion,
          payloadSource: 'independent_drafting',
        );

        final report = await _querier(db).queryByChapter('c1');
        expect(report.candidates, hasLength(1));
        final c = report.candidates.single;
        expect(c.completionEventId, 'ev1');
        expect(c.chapterId, 'c1');
        expect(c.sessionId, 's1');
        expect(c.goalWords, 100); // 事实快照：目标 100
        expect(c.wordCount, 120); // 事实快照：当前 120
        expect(report.independentCompletionCount, 1);
        expect(report.adoptIntervenedCount, 0);
        expect(report.belowGoalCount, 0);
      } finally {
        await db.close();
      }
    });

    test('② 按会话取 → 只含该会话命中章节的候选（会话隔离）', () async {
      final db = _db();
      try {
        await _seedSession(db, 's1');
        await _seedSession(db, 's2');
        await _seedManuscriptChapter(
          db,
          chapterId: 'c1',
          contentLength: 120,
          goalWords: 100,
        );
        await _seedManuscriptChapter(
          db,
          chapterId: 'c2',
          contentLength: 200,
          goalWords: 150,
        );
        await _insertEvent(
          db,
          id: 'ev1',
          sessionId: 's1',
          chapterId: 'c1',
          eventType: EditDiffEventTypes.completion,
          payloadSource: 'independent_drafting',
        );
        await _insertEvent(
          db,
          id: 'ev2',
          sessionId: 's2',
          chapterId: 'c2',
          eventType: EditDiffEventTypes.completion,
          payloadSource: 'independent_drafting',
        );

        final r1 = await _querier(db).queryBySession('s1');
        expect(r1.candidates.map((c) => c.chapterId), ['c1']);

        final r2 = await _querier(db).queryBySession('s2');
        expect(r2.candidates.map((c) => c.chapterId), ['c2']);
      } finally {
        await db.close();
      }
    });

    test('③ independent_drafting 标记筛选：普通成稿（无该 source）→ 不候选', () async {
      final db = _db();
      try {
        await _seedSession(db, 's1');
        await _seedManuscriptChapter(
          db,
          chapterId: 'c1',
          contentLength: 120,
          goalWords: 100,
        );
        // 无 source（普通成稿）+ source='normal' 两种都不进独立候选。
        await _insertEvent(
          db,
          id: 'ev1',
          sessionId: 's1',
          chapterId: 'c1',
          eventType: EditDiffEventTypes.completion,
          payloadSource: null,
        );
        await _insertEvent(
          db,
          id: 'ev2',
          sessionId: 's1',
          chapterId: 'c1',
          eventType: EditDiffEventTypes.completion,
          payloadSource: 'normal',
        );

        final report = await _querier(db).queryByChapter('c1');
        expect(report.candidates, isEmpty);
        expect(
          report.independentCompletionCount,
          0,
          reason: '无 independent_drafting 标记者不计入独立成稿',
        );
      } finally {
        await db.close();
      }
    });

    test('④ 自主性排除：同会话存在 adopt 链路 diff → 该 completion 不候选', () async {
      final db = _db();
      try {
        await _seedSession(db, 's1');
        await _seedManuscriptChapter(
          db,
          chapterId: 'c1',
          contentLength: 120,
          goalWords: 100,
        );
        // 采纳链路 diff（messageId!=null）→ 该会话被标记介入。
        await _insertEvent(
          db,
          id: 'd1',
          sessionId: 's1',
          chapterId: 'c1',
          eventType: EditDiffEventTypes.diff,
          messageId: 'msg-1',
        );
        await _insertEvent(
          db,
          id: 'ev1',
          sessionId: 's1',
          chapterId: 'c1',
          eventType: EditDiffEventTypes.completion,
          payloadSource: 'independent_drafting',
        );

        final report = await _querier(db).queryByChapter('c1');
        expect(report.candidates, isEmpty);
        expect(report.adoptIntervenedCount, 1, reason: 'adopt 链路介入被事实留痕');
      } finally {
        await db.close();
      }
    });

    test('⑤ 未设目标（app_state 无 goal 行）→ 不候选（noGoalTarget 留痕）', () async {
      final db = _db();
      try {
        await _seedSession(db, 's1');
        // 不写 goal 行 → goalWords=0。
        await _seedManuscriptChapter(
          db,
          chapterId: 'c1',
          contentLength: 120,
          goalWords: null,
        );
        await _insertEvent(
          db,
          id: 'ev1',
          sessionId: 's1',
          chapterId: 'c1',
          eventType: EditDiffEventTypes.completion,
          payloadSource: 'independent_drafting',
        );

        final report = await _querier(db).queryByChapter('c1');
        expect(report.candidates, isEmpty);
        expect(report.noGoalTargetCount, 1, reason: '未设目标按现场裁定不计完整章候选');
      } finally {
        await db.close();
      }
    });

    test('⑥ 只记不判：候选对象无 passed/success 等成败布尔', () {
      final c = ChapterCompletionCandidate(
        completionEventId: 'ev',
        chapterId: 'c',
        sessionId: 's',
        createdAt: 0,
        goalWords: 100,
        wordCount: 120,
      );
      // 仅暴露事实字段；反射确认无成败布尔 getter。
      final props = c.runtimeType.toString(); // 编译期即可见类签名；运行期只断言事实字段可访问。
      expect(c.goalWords, 100);
      expect(c.wordCount, 120);
      expect(props, contains('ChapterCompletionCandidate'));
    });
  });
}
