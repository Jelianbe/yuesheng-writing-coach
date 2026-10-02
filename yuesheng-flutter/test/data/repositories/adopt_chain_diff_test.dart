// ─────────────────────────────────────────────────────────────
// adopt_chain_diff_test — 采纳链路 vs 自主修改 diff 可区分（ADR-C133 批1 子任务B）
//
// 口径（ADR-C133 §4.1）：
//   - 自主修改 = saveChapterContent 写 diff 事件，message_id 恒 null、无 source；
//   - 采纳链路 = adoptContentToChapter 写 diff 事件，带教练消息 messageId
//     （拿不到则 messageId=null 但 payload.source='adopt' 保底区分）。
//
// 覆盖：
//   1. adoptContentToChapter(messageId:) → diff 行带 messageId + payload source=adopt
//   2. 旧调用形态（不传 messageId）→ messageId=null 但仍落 source=adopt（区分成立）
//   3. saveChapterContent diff 行 messageId 恒 null 且无 source（回归保护，防本批误改）
//   4. 聚合器集成：adopt diff（messageId 非空）不列入 M3 候选；
//      saveChapterContent diff（null，章节有诊断锚定）列入候选
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/services/m3_candidate_aggregator.dart';

void main() {
  late AppDatabase db;
  late ChapterRepository chapterRepo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    chapterRepo = ChapterRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  Future<List<EditDiffEvent>> _diffRows() =>
      (db.select(db.editDiffEvents)).get();

  test(
    '1 adoptContentToChapter(messageId:) → diff 行带 messageId + source=adopt',
    () async {
      final c = await chapterRepo.createChapter(
        manuscriptId,
        title: '章',
        content: '原文',
      );

      await chapterRepo.adoptContentToChapter(c, '原文新尾', messageId: 'msg-123');

      final rows = await _diffRows();
      expect(rows.length, 1);
      expect(rows.first.eventType, 'diff');
      expect(rows.first.messageId, 'msg-123');
      expect(rows.first.payload, contains('"source":"adopt"'));
      // 内容落库仍正确（采纳语义未被本批破坏）
      expect((await chapterRepo.getChapter(c))?.content, '原文新尾');
    },
  );

  test('2 旧调用形态（不传 messageId）仍落 source=adopt（数据层区分成立）', () async {
    final c = await chapterRepo.createChapter(
      manuscriptId,
      title: '章',
      content: '原文',
    );

    // 旧调用形态：仅 (chapterId, newContent)，messageId 默认 null
    await chapterRepo.adoptContentToChapter(c, '原文新尾');

    final rows = await _diffRows();
    expect(rows.length, 1);
    expect(rows.first.messageId, isNull);
    // 即便拿不到 messageId，payload.source=adopt 仍使采纳链路可识别
    expect(rows.first.payload, contains('"source":"adopt"'));
  });

  test(
    '3 saveChapterContent diff 行 messageId 恒 null 且无 source（回归保护）',
    () async {
      final c = await chapterRepo.createChapter(
        manuscriptId,
        title: '章',
        content: '旧文',
      );

      await chapterRepo.saveChapterContent(c, '旧文X');

      final rows = await _diffRows();
      expect(rows.length, 1);
      // 自主修改语义：message_id 恒 null
      expect(rows.first.messageId, isNull);
      // saveChapterContent 不写 source（与采纳链路 payload 形态区分）
      expect(rows.first.payload, isNot(contains('"source"')));
    },
  );

  test('4 聚合器集成：adopt diff 排除 / 自主 diff（有锚定）列入 M3 候选', () async {
    // 采纳链路章节（带教练消息 id）
    final adoptCh = await chapterRepo.createChapter(
      manuscriptId,
      title: '采纳章',
      content: '原文',
    );
    await chapterRepo.adoptContentToChapter(
      adoptCh,
      '原文新尾',
      messageId: 'msg-adopt',
    );

    // 自主修改章节（无 messageId），章节带已学症候诊断锚定
    final autoCh = await chapterRepo.createChapter(
      manuscriptId,
      title: '自主章',
      content: '旧',
    );
    await chapterRepo.saveChapterContent(autoCh, '旧X');

    final rows = await _diffRows();
    expect(rows.length, 2);
    final adoptRow = rows.firstWhere((r) => r.messageId != null);
    final autoRow = rows.firstWhere((r) => r.messageId == null);

    final report = aggregateM3Candidates(
      diffEvents: rows,
      anchorsByChapter: {
        autoCh: M3ChapterAnchor(
          chapterId: autoCh,
          syndromes: const [
            M3AnchorSyndrome(syndromeId: 'P001', syndromeName: '指代不清'),
          ],
        ),
      },
    );

    // 采纳链路被排除（计入 adoptedChainDiffCount）
    expect(report.adoptedChainDiffCount, 1);
    expect(report.selfOwnedDiffCount, 1);
    // 仅自主修改行入选 M3 候选；采纳行不入选
    expect(report.candidates.map((e) => e.diffEventId), [autoRow.id]);
    expect(report.candidates.any((e) => e.diffEventId == adoptRow.id), isFalse);
  });

  test('5 旧调用形态采纳（messageId=null 但 payload.source=adopt）经聚合器仍被排除', () async {
    // 拿不到 messageId 的采纳形态（provider 包装层/旧调用）
    final adoptCh = await chapterRepo.createChapter(
      manuscriptId,
      title: '无id采纳章',
      content: '原文',
    );
    await chapterRepo.adoptContentToChapter(adoptCh, '原文新尾');

    // 同章自主修改（saveChapterContent，无 source）
    await chapterRepo.saveChapterContent(adoptCh, '原文新尾X');

    final rows = await _diffRows();
    expect(rows.length, 2);

    final report = aggregateM3Candidates(
      diffEvents: rows,
      anchorsByChapter: {
        adoptCh: M3ChapterAnchor(
          chapterId: adoptCh,
          syndromes: const [
            M3AnchorSyndrome(syndromeId: 'P001', syndromeName: '指代不清'),
          ],
        ),
      },
    );

    // 两条 diff：一条 source=adopt（无 messageId），一条自主修改
    expect(report.selfOwnedDiffCount, 1, reason: '仅 saveChapterContent 行计自主修改');
    expect(
      report.adoptedChainDiffCount,
      1,
      reason: '旧调用形态采纳经 payload.source 识别排除',
    );
    // 仅自主修改行入选候选；source=adopt 行即使 messageId=null 也不入选
    expect(report.candidateCount, 1);
    expect(
      report.candidates.single.afterText,
      contains('X'),
      reason: '入选候选的是自主修改行',
    );
  });
}
