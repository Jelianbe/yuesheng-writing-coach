// ─────────────────────────────────────────────────────────────
// fact_batch_flow_test — C78 批次3 FR-10 批次沉淀计数链路
//
// 覆盖：
//   1. DiagnosisCommitter.applyFactExtractionFromContent 返回净新增断言数：
//      首轮 = 新增条数；重喂同块 = 0（重抽被三元组合并，不夸大「沉淀」）；
//      追加一条新断言再喂 = 1
//   2. 返回的 manuscriptId 与章节所属作品一致（提示卡跳转上下文）
//   3. FactBatchRegistry：count>0 登记 / count=0 不登记 / 同 id 以最新为准
//
// 提示卡 UI 侧契约（messageId → 卡片）由 fact_batch_card 的 widget 测试覆盖。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/providers/fact_batch_providers.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';

void main() {
  late AppDatabase db;
  late String manuscriptId;
  late String chapterId;

  const factBlock = '''
[YS_FACT]
{
  "characters":[{"name":"王建国","assertions":[{"attribute":"性格","value":"沉默寡言","chapter":1},{"attribute":"职业","value":"捕快","chapter":1}]}]
}
[/YS_FACT]
''';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
    chapterId = await ChapterRepository(db).createChapter(
      manuscriptId,
      title: '第一章',
      content: '王建国站在巷口。',
      sortOrder: 1,
    );
  });

  tearDown(() async => db.close());

  DiagnosisCommitter buildCommitter() {
    return DiagnosisCommitter(
      sessionRepo: SessionRepository(db),
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      db: db,
      characterFactRepo: CharacterFactRepository(db),
    );
  }

  group('applyFactExtractionFromContent 净新增计数', () {
    test('首轮返回新增条数 + manuscriptId；重喂同块返回 0', () async {
      final committer = buildCommitter();
      final first = await committer.applyFactExtractionFromContent(
        sessionId: 'sess-1',
        fullContent: factBlock,
        primaryRef: ReferenceItem(
          refType: 'chapter',
          refId: chapterId,
          title: '第一章',
          isPrimary: 1,
          manuscriptId: manuscriptId,
        ),
      );
      expect(first.count, 2, reason: '两条断言均净新增');
      expect(first.manuscriptId, manuscriptId, reason: '提示卡跳转需要作品上下文');

      final second = await committer.applyFactExtractionFromContent(
        sessionId: 'sess-1',
        fullContent: factBlock,
        primaryRef: ReferenceItem(
          refType: 'chapter',
          refId: chapterId,
          title: '第一章',
          isPrimary: 1,
          manuscriptId: manuscriptId,
        ),
      );
      expect(second.count, 0, reason: 'AI 重抽同三元组被合并，不计入「沉淀」');
    });

    test('重喂同块 + 追加一条新断言 → 只计新增的 1 条', () async {
      final committer = buildCommitter();
      final ref = ReferenceItem(
        refType: 'chapter',
        refId: chapterId,
        title: '第一章',
        isPrimary: 1,
        manuscriptId: manuscriptId,
      );
      await committer.applyFactExtractionFromContent(
        sessionId: 'sess-1',
        fullContent: factBlock,
        primaryRef: ref,
      );

      const appended = '''
[YS_FACT]
{
  "characters":[{"name":"王建国","assertions":[{"attribute":"性格","value":"沉默寡言","chapter":1},{"attribute":"职业","value":"捕快","chapter":1},{"attribute":"身世","value":"孤儿","chapter":1}]}]
}
[/YS_FACT]
''';
      final outcome = await committer.applyFactExtractionFromContent(
        sessionId: 'sess-1',
        fullContent: appended,
        primaryRef: ref,
      );
      expect(outcome.count, 1, reason: '只有「身世·孤儿」是净新增');
    });
  });

  group('FactBatchRegistry（内存态，ADR-C78 冲突 C）', () {
    test('count>0 登记；count=0 不登记；同 messageId 以最新为准', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final registry = container.read(factBatchProvider.notifier);

      registry.register(messageId: 'm1', count: 0, manuscriptId: 'ms1');
      expect(container.read(factBatchProvider), isEmpty, reason: '无新增不发提示卡');

      registry.register(messageId: 'm1', count: 3, manuscriptId: 'ms1');
      final record = container.read(factBatchProvider)['m1']!;
      expect(record.count, 3);
      expect(record.manuscriptId, 'ms1');
      expect(record.at, greaterThan(0));

      registry.register(messageId: 'm1', count: 5, manuscriptId: 'ms1');
      expect(container.read(factBatchProvider)['m1']!.count, 5);
    });
  });
}
