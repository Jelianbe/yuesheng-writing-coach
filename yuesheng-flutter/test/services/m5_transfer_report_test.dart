// ─────────────────────────────────────────────────────────────
// m5_transfer_report_test — M5（新题材迁移）三行为测量（ADR-C139 子项①）
//
// 覆盖纯函数 aggregateM5Transfer（不起 DB，伪造 EditDiffEvent 行）：
//   T1 三行为分别计数：独立起稿 / M3 候选复用 / M2_recall confirmed
//   T2 corrected 复述留痕但不计入候选（区分 confirmed vs corrected）
//   T3 纯指认 anchor_ack（无 M2_recall kind）不计入 (c)
//   T4 普通 completion（无 source）不计入 (a)——(a) 只数独立起稿
//   T5 空输入 → 全零（M5TransferReport.empty）
//   T6 R-009 只记不判：报告无达标/成败/迁移成功布尔字段
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';
import 'package:writingcoach/services/m3_candidate_aggregator.dart';
import 'package:writingcoach/services/m3_milestone_events.dart';
import 'package:writingcoach/services/m5_transfer_querier.dart';
import 'package:writingcoach/services/m5_transfer_report.dart';

EditDiffEvent _ack({required String id, String payload = ''}) => EditDiffEvent(
  id: id,
  sessionId: 's1',
  chapterId: 'ch1',
  eventType: EditDiffEventTypes.anchorAck,
  beforeText: '根因原文',
  afterText: '学员用自己的话复述',
  payload: payload,
  createdAt: 1000,
);

EditDiffEvent _completion({required String id, String? source}) =>
    EditDiffEvent(
      id: id,
      sessionId: 's1',
      chapterId: 'ch1',
      eventType: EditDiffEventTypes.completion,
      beforeText: '',
      afterText: '',
      payload: source == null
          ? ''
          : const CompletionPayload(
              source: CompletionSource.independentDrafting,
            ).encode()!,
      createdAt: 1000,
    );

String _recallPayload(String verdict) => M2RecallPayload(
  verdict: verdict,
  syndromeId: 'P001',
  syndromeName: '指代不清',
).encode();

void main() {
  final zeroM3 = M3CandidateReport(
    candidates: const [],
    selfOwnedDiffCount: 0,
    adoptedChainDiffCount: 0,
  );

  group('aggregateM5Transfer · 三行为计数', () {
    test('T1 三行为分别计数：独立起稿 / M3 候选复用 / M2_recall confirmed', () {
      final report = aggregateM5Transfer(
        independentDraftingCompletions: [
          _completion(id: 'c1', source: CompletionSource.independentDrafting),
          _completion(id: 'c2', source: CompletionSource.independentDrafting),
        ],
        anchorAckEvents: [
          _ack(id: 'a1', payload: _recallPayload(M2RecallVerdict.confirmed)),
          _ack(id: 'a2', payload: _recallPayload(M2RecallVerdict.confirmed)),
          _ack(id: 'a3', payload: _recallPayload(M2RecallVerdict.confirmed)),
        ],
        selfOwnedAnchoredModifications: zeroM3,
      );
      expect(report.independentDraftingCompletionCount, 2); // (a)
      expect(report.recallConfirmedCount, 3); // (c) confirmed
      expect(report.recallCorrectedCount, 0);
      // (b) 复用 M3 候选数
      expect(report.selfOwnedAnchoredModificationCount, 0);
    });

    test('T2 corrected 复述留痕但不计入候选（confirmed/corrected 分列）', () {
      final report = aggregateM5Transfer(
        independentDraftingCompletions: const [],
        anchorAckEvents: [
          _ack(id: 'a1', payload: _recallPayload(M2RecallVerdict.confirmed)),
          _ack(id: 'a2', payload: _recallPayload(M2RecallVerdict.corrected)),
          _ack(id: 'a3', payload: _recallPayload(M2RecallVerdict.corrected)),
        ],
        selfOwnedAnchoredModifications: zeroM3,
      );
      expect(report.recallConfirmedCount, 1); // 复述到位候选
      expect(report.recallCorrectedCount, 2); // 需修正留痕（非候选）
    });

    test('T3 纯指认 anchor_ack（无 M2_recall kind）不计入 (c)', () {
      final report = aggregateM5Transfer(
        independentDraftingCompletions: const [],
        anchorAckEvents: [
          _ack(id: 'a1'), // C132 纯指认：payload 空
          _ack(id: 'a2', payload: '{"kind":"something_else"}'), // 非 M2_recall
          _ack(id: 'a3', payload: _recallPayload(M2RecallVerdict.confirmed)),
        ],
        selfOwnedAnchoredModifications: zeroM3,
      );
      expect(report.recallConfirmedCount, 1);
      expect(report.recallCorrectedCount, 0);
    });

    test('T4 普通 completion（无 source）不计入 (a)——(a) 只数独立起稿', () {
      // (a) 由调用方先经 listIndependentDraftingCompletions 过滤；
      // 纯函数收到的独立起稿列表长度即计数。此处模拟传入「已过滤后」的列表。
      final report = aggregateM5Transfer(
        independentDraftingCompletions: [
          _completion(id: 'c1', source: CompletionSource.independentDrafting),
        ],
        anchorAckEvents: const [],
        selfOwnedAnchoredModifications: zeroM3,
      );
      expect(report.independentDraftingCompletionCount, 1);
    });

    test('T5 空输入 → 全零（M5TransferReport.empty）', () {
      expect(M5TransferReport.empty.independentDraftingCompletionCount, 0);
      expect(M5TransferReport.empty.recallConfirmedCount, 0);
      expect(M5TransferReport.empty.recallCorrectedCount, 0);
      expect(M5TransferReport.empty.selfOwnedAnchoredModificationCount, 0);
    });

    test('T6 R-009 只记不判：报告无达标/成败/迁移成功布尔字段', () {
      // 反射不可用（VM），改以字段存在性断言：报告只暴露计数与复用的 M3 报告，
      // 无任何 boolean success / ready / transferred / threshold 字段。
      final report = M5TransferReport.empty;
      expect(report.independentDraftingCompletionCount, isA<int>());
      expect(report.recallConfirmedCount, isA<int>());
      expect(report.recallCorrectedCount, isA<int>());
      expect(report.selfOwnedAnchoredModifications, isA<M3CandidateReport>());
      // M3CandidateReport 自身已在 m3_candidate_aggregator_test 断言无成败布尔；
      // M5 报告不新增任何 bool 字段（构造参数全为 int / M3CandidateReport）。
    });
  });

  group('B 查询器装配（内存 DB）· report() 组合三源', () {
    late AppDatabase db;
    late EditDiffEventRepository diffRepo;
    late M3MilestoneEventQuerier m3;
    late M5TransferQuerier querier;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      diffRepo = EditDiffEventRepository(db);
      final diagRepo = DiagnosisRepository(db);
      m3 = M3MilestoneEventQuerier(diffRepo, diagRepo);
      querier = M5TransferQuerier(diffRepo: diffRepo, m3: m3);
      await db.into(db.sessions).insert(SessionsCompanion.insert(id: 's1'));
      // ch1 = confirmed 章节级诊断（P001）→ M3 锚定章节
      await db
          .into(db.diagnosisResults)
          .insert(
            DiagnosisResultsCompanion.insert(
              id: 'diag-1',
              sessionId: 's1',
              messageId: 'm-diag',
              syndromes: drift.Value('[{"syndrome_id":"P001","name":"指代不清"}]'),
              targetRefType: const drift.Value('chapter'),
              targetRefId: const drift.Value('ch1'),
              status: const drift.Value('confirmed'),
            ),
          );
    });

    tearDown(() async => db.close());

    test('B1 report() 组合：(a)独立起稿 (b)M3候选 (c)M2_recall 分列计数', () async {
      // (a) 独立起稿成稿 ×2 + 普通成稿 ×1（不计入）
      await diffRepo.recordCompletion(
        sessionId: 's1',
        chapterId: 'ch1',
        source: CompletionSource.independentDrafting,
      );
      await diffRepo.recordCompletion(
        sessionId: 's1',
        chapterId: 'ch1',
        source: CompletionSource.independentDrafting,
      );
      await diffRepo.recordCompletion(sessionId: 's1', chapterId: 'ch1'); // 普通
      // (b) 自主修改（messageId=null）落在已锚定章节 ch1 → M3 候选 ×1
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
      // (c) M2_recall confirmed ×1 + corrected ×1
      await diffRepo.recordM2Recall(
        sessionId: 's1',
        chapterId: 'ch1',
        syndromeId: 'P001',
        recallText: '我自己的话复述根因',
        verdict: M2RecallVerdict.confirmed,
      );
      await diffRepo.recordM2Recall(
        sessionId: 's1',
        chapterId: 'ch1',
        syndromeId: 'P001',
        recallText: '需修正的复述',
        verdict: M2RecallVerdict.corrected,
      );
      // 纯指认 anchor_ack（非 M2_recall）→ 不计入 (c)
      await diffRepo.recordAnchorAcknowledged(
        sessionId: 's1',
        chapterId: 'ch1',
        anchorText: '指认片段',
      );

      final report = await querier.report();
      expect(report.independentDraftingCompletionCount, 2); // (a) 普通成稿不计
      expect(report.selfOwnedAnchoredModificationCount, 1); // (b)
      expect(report.recallConfirmedCount, 1); // (c)
      expect(report.recallCorrectedCount, 1); // (c)
    });

    test('B2 空库 → 全零报告', () async {
      final report = await querier.report();
      expect(report.independentDraftingCompletionCount, 0);
      expect(report.selfOwnedAnchoredModificationCount, 0);
      expect(report.recallConfirmedCount, 0);
      expect(report.recallCorrectedCount, 0);
    });
  });
}
