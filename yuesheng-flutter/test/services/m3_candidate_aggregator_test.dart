// ─────────────────────────────────────────────────────────────
// m3_candidate_aggregator_test — M3 门槛候选事件聚合（ADR-C133 批1 子任务 M3）
//
// 覆盖：
//   A 纯函数组（不起 DB）：
//     A1 自主修改 + 章节命中 → 返回候选（绝对值）
//     A2 无诊断章节的自主修改 → 不候选（事实计数仍记）
//     A3 片段级重叠附加事实（hitLevel 升级，不改主判据）
//     A4 messageId 非空（adopt 形态）→ 不列入 M3 候选
//     A5 只记不判：候选记录无成败布尔字段
//     A6 空 diff 列表 → 全零
//     A7/A8 首次写入 / 全章清空 → 不误判（仍是修改）
//     A9 混入 anchor_ack / completion 事件 → 不进候选
//   B 查询工具组（内存 DB）：
//     B1 按章节过滤   B2 按会话过滤   B3 按时间段过滤
//     B4 锚定上下文构建：confirmed chapter 诊断入选；
//        pending / replaced / manuscript 级诊断被排除；anchor_ack 归组
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';
import 'package:writingcoach/services/m3_candidate_aggregator.dart';
import 'package:writingcoach/services/m3_milestone_events.dart';

EditDiffEvent _diff({
  required String id,
  String chapterId = 'ch1',
  String sessionId = 's1',
  String? messageId,
  String? afterText,
  String eventType = 'diff',
  String payload = '',
  int createdAt = 1000,
}) => EditDiffEvent(
  id: id,
  sessionId: sessionId,
  chapterId: chapterId,
  messageId: messageId,
  eventType: eventType,
  beforeText: '旧文',
  afterText: afterText,
  payload: payload,
  createdAt: createdAt,
);

Map<String, M3ChapterAnchor> _anchors({
  String chapterId = 'ch1',
  List<String> anchorTexts = const [],
}) => {
  chapterId: M3ChapterAnchor(
    chapterId: chapterId,
    syndromes: const [
      M3AnchorSyndrome(syndromeId: 'P001', syndromeName: '指代不清'),
    ],
    anchorTexts: anchorTexts,
  ),
};

void main() {
  group('A 纯函数聚合', () {
    test('A1 自主修改（messageId=null）+ 章节命中 → 返回候选（绝对值）', () {
      final report = aggregateM3Candidates(
        diffEvents: [_diff(id: 'd1')],
        anchorsByChapter: _anchors(),
      );
      expect(report.candidateCount, 1);
      expect(report.selfOwnedDiffCount, 1);
      expect(report.adoptedChainDiffCount, 0);
      final c = report.candidates.single;
      expect(c.diffEventId, 'd1');
      expect(c.chapterId, 'ch1');
      expect(c.messageId == null, isTrue, reason: '要素①事实留痕：messageId 恒 null');
      expect(c.anchoredSyndromes.single.syndromeId, 'P001');
      expect(c.hitLevel, M3AnchorHitLevel.chapter);
    });

    test('A2 无诊断章节的自主修改 → 不候选（事实计数仍记）', () {
      final report = aggregateM3Candidates(
        diffEvents: [_diff(id: 'd1', chapterId: 'ch-no-anchor')],
        anchorsByChapter: _anchors(),
      );
      expect(report.candidateCount, 0);
      expect(report.selfOwnedDiffCount, 1, reason: '自主修改事实全量计数，不裁剪');
    });

    test('A3 片段级重叠附加事实：hitLevel 升级但不改主判据', () {
      final hit = aggregateM3Candidates(
        diffEvents: [_diff(id: 'd1', afterText: '窗外的雨下了起来')],
        anchorsByChapter: _anchors(anchorTexts: ['窗外的雨']),
      );
      expect(hit.candidateCount, 1);
      expect(
        hit.candidates.single.hitLevel,
        M3AnchorHitLevel.chapterWithFragment,
      );

      // 无指认文本/无重叠 → 仍章节级候选（片段不重叠不推翻主判据）
      final plain = aggregateM3Candidates(
        diffEvents: [_diff(id: 'd2', afterText: '完全无关的段落')],
        anchorsByChapter: _anchors(anchorTexts: ['窗外的雨']),
      );
      expect(plain.candidateCount, 1);
      expect(plain.candidates.single.hitLevel, M3AnchorHitLevel.chapter);
    });

    test('A4 messageId 非空（adopt 形态）→ 不列入 M3 候选', () {
      final report = aggregateM3Candidates(
        diffEvents: [_diff(id: 'd1', messageId: 'msg-adopt-1')],
        anchorsByChapter: _anchors(),
      );
      expect(report.candidateCount, 0);
      expect(report.selfOwnedDiffCount, 0);
      expect(report.adoptedChainDiffCount, 1, reason: '采纳链路计数排除留痕');
    });

    test('A4b messageId=null 但 payload.source=adopt（拿不到 messageId 的 adopt 形态）'
        '→ 不列入候选、计入采纳排除', () {
      final report = aggregateM3Candidates(
        diffEvents: [
          _diff(id: 'd1', payload: '{"diff_segments":1,"source":"adopt"}'),
        ],
        anchorsByChapter: _anchors(),
      );
      expect(report.candidateCount, 0);
      expect(report.selfOwnedDiffCount, 0);
      expect(
        report.adoptedChainDiffCount,
        1,
        reason: 'messageId=null 但 source=adopt 仍属采纳链路排除（批4 修复）',
      );
    });

    test('A4c messageId=null 且 payload 无 source（纯自主修改）→ 仍列入候选', () {
      final report = aggregateM3Candidates(
        diffEvents: [_diff(id: 'd1', payload: '{"diff_segments":1}')],
        anchorsByChapter: _anchors(),
      );
      expect(report.candidateCount, 1);
      expect(report.selfOwnedDiffCount, 1);
      expect(report.adoptedChainDiffCount, 0);
    });

    test('A4d payload 损坏 JSON / 空串 → 按自主修改处理（不误排除）', () {
      final broken = aggregateM3Candidates(
        diffEvents: [_diff(id: 'd1', payload: 'not-json{{')],
        anchorsByChapter: _anchors(),
      );
      expect(broken.candidateCount, 1);
      expect(broken.selfOwnedDiffCount, 1);
      expect(broken.adoptedChainDiffCount, 0);

      final empty = aggregateM3Candidates(
        diffEvents: [_diff(id: 'd2')], // payload 默认 ''
        anchorsByChapter: _anchors(),
      );
      expect(empty.candidateCount, 1);
      expect(empty.adoptedChainDiffCount, 0);
    });

    test('A5 只记不判：候选记录无成败判定布尔字段', () {
      final report = aggregateM3Candidates(
        diffEvents: [_diff(id: 'd1')],
        anchorsByChapter: _anchors(),
      );
      final c = report.candidates.single as dynamic;
      // messageId=null 是事实留痕，不是成败布尔
      expect(c.messageId == null, isTrue);
      // 不存在任何成败语义的字段
      expect(() => c.passed, throwsA(isA<NoSuchMethodError>()));
      expect(() => c.success, throwsA(isA<NoSuchMethodError>()));
      expect(() => c.reached, throwsA(isA<NoSuchMethodError>()));
      expect(() => c.improved, throwsA(isA<NoSuchMethodError>()));
      // 计数为绝对值，无达标阈值语义（报告上不提供目标/达标字段）
      final dynReport = report as dynamic;
      expect(() => dynReport.targetReached, throwsA(isA<NoSuchMethodError>()));
    });

    test('A6 空 diff 列表 → 全零', () {
      final report = aggregateM3Candidates(
        diffEvents: const [],
        anchorsByChapter: _anchors(),
      );
      expect(report.candidateCount, 0);
      expect(report.selfOwnedDiffCount, 0);
      expect(report.adoptedChainDiffCount, 0);
    });

    test('A7/A8 首次写入（beforeText 空）与全章清空（afterText 空）仍判候选', () {
      // 首次写入：afterText 非空、章节锚定 → 候选（要素只看 messageId+章节）
      final firstWrite = aggregateM3Candidates(
        diffEvents: [_diff(id: 'd1', afterText: '第一章 出发')],
        anchorsByChapter: _anchors(),
      );
      expect(firstWrite.candidateCount, 1);

      // 全章清空：afterText 空 → 候选仍成立，但片段重叠事实为 false
      final cleared = aggregateM3Candidates(
        diffEvents: [_diff(id: 'd2', afterText: '')],
        anchorsByChapter: _anchors(anchorTexts: ['第一章 出发']),
      );
      expect(cleared.candidateCount, 1);
      expect(cleared.candidates.single.hitLevel, M3AnchorHitLevel.chapter);
    });

    test('A9 混入 anchor_ack / completion 事件 → 不进候选、不计自主修改', () {
      final report = aggregateM3Candidates(
        diffEvents: [
          _diff(id: 'd1', eventType: 'anchor_ack'),
          _diff(id: 'd2', eventType: 'completion'),
          _diff(id: 'd3'), // 唯一真 diff
        ],
        anchorsByChapter: _anchors(),
      );
      expect(report.candidateCount, 1);
      expect(report.selfOwnedDiffCount, 1);
      expect(report.adoptedChainDiffCount, 0);
    });
  });

  group('B 查询工具（内存 DB）', () {
    late AppDatabase db;
    late EditDiffEventRepository diffRepo;
    late DiagnosisRepository diagRepo;
    late M3MilestoneEventQuerier querier;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      diffRepo = EditDiffEventRepository(db);
      diagRepo = DiagnosisRepository(db);
      querier = M3MilestoneEventQuerier(diffRepo, diagRepo);
      // 会话行：diagnosis_results.sessionId 外键引用 sessions.id
      await db.into(db.sessions).insert(SessionsCompanion.insert(id: 's1'));
      // 章节锚定：ch1 = confirmed 章节级诊断（P001+P002）
      await db
          .into(db.diagnosisResults)
          .insert(
            DiagnosisResultsCompanion.insert(
              id: 'diag-1',
              sessionId: 's1',
              messageId: 'm-diag',
              syndromes: drift.Value(
                '[{"syndrome_id":"P001","name":"指代不清"},'
                '{"syndrome_id":"P002","name":"动词弱"}]',
              ),
              targetRefType: const drift.Value('chapter'),
              targetRefId: const drift.Value('ch1'),
              status: const drift.Value('confirmed'),
            ),
          );
    });

    tearDown(() async => db.close());

    test('B1 按章节过滤：ch1 自主修改入候选，ch2 自主修改不入', () async {
      await diffRepo.recordDiff(
        EditDiffInput(
          sessionId: 's1',
          chapterId: 'ch1',
          anchorStart: 0,
          anchorEnd: 2,
          beforeText: '旧',
          afterText: '新',
          diffSegments: 1,
        ),
      );
      await diffRepo.recordDiff(
        EditDiffInput(
          sessionId: 's1',
          chapterId: 'ch2', // 无锚定章节
          anchorStart: 0,
          anchorEnd: 2,
          beforeText: '旧',
          afterText: '新',
          diffSegments: 1,
        ),
      );

      final ch1 = await querier.queryByChapter('ch1');
      expect(ch1.candidateCount, 1);
      expect(ch1.candidates.single.anchoredSyndromes.length, 2);

      final ch2 = await querier.queryByChapter('ch2');
      expect(ch2.candidateCount, 0);
      expect(ch2.selfOwnedDiffCount, 1);
    });

    test('B2 按会话过滤：只取目标会话的自主修改', () async {
      await db.into(db.sessions).insert(SessionsCompanion.insert(id: 's2'));
      await diffRepo.recordDiff(
        EditDiffInput(
          sessionId: 's1',
          chapterId: 'ch1',
          anchorStart: 0,
          anchorEnd: 2,
          beforeText: '旧',
          afterText: '新一',
          diffSegments: 1,
        ),
      );
      await diffRepo.recordDiff(
        EditDiffInput(
          sessionId: 's2',
          chapterId: 'ch1',
          anchorStart: 0,
          anchorEnd: 2,
          beforeText: '旧',
          afterText: '新二',
          diffSegments: 1,
        ),
      );

      final s2 = await querier.queryBySession('s2');
      expect(s2.candidateCount, 1);
      expect(s2.candidates.single.afterText, '新二');
    });

    test('B3 按时间段过滤（createdAt 闭区间）', () async {
      // 直接落库以控制 createdAt
      for (final t in [100, 200, 300]) {
        await db
            .into(db.editDiffEvents)
            .insert(
              EditDiffEventsCompanion.insert(
                id: 'd-t$t',
                chapterId: 'ch1',
                eventType: 'diff',
                sessionId: const drift.Value('s1'),
                afterText: drift.Value('t$t'),
                createdAt: drift.Value(t),
              ),
            );
      }
      final mid = await querier.queryByTimeRange(fromSec: 150, toSec: 250);
      expect(mid.candidateCount, 1);
      expect(mid.candidates.single.createdAt, 200);

      final all = await querier.queryByTimeRange();
      expect(all.candidateCount, 3);

      final tail = await querier.queryByTimeRange(fromSec: 250);
      expect(tail.candidateCount, 1);
      expect(tail.candidates.single.createdAt, 300);
    });

    test(
      'B4 锚定上下文构建：confirmed chapter 入选；pending/replaced/manuscript 排除',
      () async {
        // pending 章节级诊断 → 排除
        await db
            .into(db.diagnosisResults)
            .insert(
              DiagnosisResultsCompanion.insert(
                id: 'diag-pending',
                sessionId: 's1',
                messageId: 'm-pending',
                syndromes: drift.Value('[{"syndrome_id":"P900","name":"假症候"}]'),
                targetRefType: const drift.Value('chapter'),
                targetRefId: const drift.Value('ch-pending'),
                status: const drift.Value('pending'),
              ),
            );
        // manuscript 级 confirmed 诊断 → 排除（非章节锚定）
        await db
            .into(db.diagnosisResults)
            .insert(
              DiagnosisResultsCompanion.insert(
                id: 'diag-manu',
                sessionId: 's1',
                messageId: 'm-manu',
                syndromes: drift.Value(
                  '[{"syndrome_id":"P901","name":"整体问题"}]',
                ),
                targetRefType: const drift.Value('manuscript'),
                targetRefId: const drift.Value('ms-x'),
                status: const drift.Value('confirmed'),
              ),
            );
        // anchor_ack 指认片段归入 ch1
        await diffRepo.recordAnchorAcknowledged(
          sessionId: 's1',
          chapterId: 'ch1',
          anchorText: '他跑了过去',
        );

        final anchors = await querier.buildChapterAnchors();
        expect(anchors['ch1']!.syndromes.length, 2);
        expect(anchors['ch1']!.anchorTexts, contains('他跑了过去'));
        expect(
          anchors.containsKey('ch-pending'),
          isFalse,
          reason: 'pending 非权威诊断',
        );
        expect(
          anchors.containsKey('ms-x'),
          isFalse,
          reason: 'manuscript 级非章节锚定',
        );

        // 端到端：ch-pending 的自主修改不候选（pending 不算已学）
        await diffRepo.recordDiff(
          EditDiffInput(
            sessionId: 's1',
            chapterId: 'ch-pending',
            anchorStart: 0,
            anchorEnd: 2,
            beforeText: '旧',
            afterText: '新',
            diffSegments: 1,
          ),
        );
        final pendingChapter = await querier.queryByChapter('ch-pending');
        expect(pendingChapter.candidateCount, 0);
        expect(pendingChapter.selfOwnedDiffCount, 1);
      },
    );

    // B5 ADR-C134 批3（M4a）：独立起稿成稿事件查询器——只记不判，
    // 只做事实过滤（completion + payload.source=independent_drafting），
    // 不含达标/成败判定；普通成稿事件被排除。
    test('B5 独立起稿成稿事件可观测：只过滤带标记的 completion', () async {
      // 普通成稿（无标记）。
      await diffRepo.recordCompletion(sessionId: 's1', chapterId: 'ch1');
      // 独立起稿成稿（带标记）。
      await diffRepo.recordCompletion(
        sessionId: 's1',
        chapterId: 'ch1',
        source: CompletionSource.independentDrafting,
      );
      // 一条 diff（非 completion）——不应混入。
      await diffRepo.recordDiff(
        EditDiffInput(
          sessionId: 's1',
          chapterId: 'ch1',
          anchorStart: 0,
          anchorEnd: 2,
          beforeText: '旧',
          afterText: '新',
          diffSegments: 1,
        ),
      );

      final list = await querier.listIndependentDraftingCompletions();
      expect(list, hasLength(1), reason: '只取带 independent_drafting 标记的成稿');
      expect(list.single.chapterId, 'ch1');
      expect(list.single.eventType, EditDiffEventTypes.completion);
      final decoded = CompletionPayload.tryDecode(list.single.payload);
      expect(decoded?.source, CompletionSource.independentDrafting);
    });
  });
}
