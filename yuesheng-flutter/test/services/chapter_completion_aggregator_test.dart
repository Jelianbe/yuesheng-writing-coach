// ─────────────────────────────────────────────────────────────
// chapter_completion_aggregator_test — M4 第二格「独立成完整章」完成候选聚合
//   （ADR-C137 批1；覆盖 ADR §6 验收 2）
//
// 覆盖（纯函数，不起 DB；复用 EditDiffEvent 直接构造）：
//   C1 三要素齐备 → 产生候选（绝对值，无成败布尔）
//   C2 缺①：普通成稿（无 independent_drafting source）→ 不候选
//   C3 缺②：同会话存在 adopt 链路介入 → 不候选（计 adoptIntervened）
//   C4 缺③a：goalWords=0（未设目标）→ 不候选（计 noGoalTarget）
//   C5 缺③b：字数未达目标 → 不候选（计 belowGoal）
//   C6 只记不判：候选/报告无 passed/success/reached 字段
//   C7 空事件列表 → 全零
//   C8 adopt 两种形态（messageId 透传 / payload.source=adopt）都算介入
//   C9 completion.sessionId 为空 → 按章节判定自主性
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';
import 'package:writingcoach/services/chapter_completion_aggregator.dart';

EditDiffEvent _row({
  required String id,
  String eventType = EditDiffEventTypes.completion,
  String chapterId = 'ch1',
  String sessionId = 's1',
  String? messageId,
  String? payload,
  int createdAt = 1000,
}) => EditDiffEvent(
  id: id,
  sessionId: sessionId,
  chapterId: chapterId,
  messageId: messageId,
  eventType: eventType,
  beforeText: '',
  afterText: '',
  payload: payload ?? '',
  createdAt: createdAt,
);

/// 一条带 independent_drafting 标记的成稿事件。
EditDiffEvent _independentCompletion({
  required String id,
  String chapterId = 'ch1',
  String sessionId = 's1',
}) => _row(
  id: id,
  chapterId: chapterId,
  sessionId: sessionId,
  payload: const CompletionPayload(
    source: CompletionSource.independentDrafting,
  ).encode(),
);

void main() {
  group('完成候选聚合（纯函数）', () {
    test('C1 三要素齐备 → 产生候选（绝对值，事实快照）', () {
      final report = aggregateChapterCompletionCandidates(
        events: [_independentCompletion(id: 'c1')],
        goalWordsByChapter: {'ch1': 1000},
        wordCountByChapter: {'ch1': 1200},
      );
      expect(report.candidateCount, 1);
      expect(report.independentCompletionCount, 1);
      expect(report.adoptIntervenedCount, 0);
      expect(report.noGoalTargetCount, 0);
      expect(report.belowGoalCount, 0);
      final c = report.candidates.single;
      expect(c.completionEventId, 'c1');
      expect(c.chapterId, 'ch1');
      expect(c.sessionId, 's1');
      expect(c.goalWords, 1000);
      expect(c.wordCount, 1200);
    });

    test('C2 缺①：普通成稿（无 independent_drafting source）→ 不候选', () {
      final report = aggregateChapterCompletionCandidates(
        events: [_row(id: 'c1', payload: null)], // 普通成稿，无标记
        goalWordsByChapter: {'ch1': 1000},
        wordCountByChapter: {'ch1': 1200},
      );
      expect(report.candidateCount, 0);
      expect(report.independentCompletionCount, 0, reason: '无标记成稿不进独立候选计数');
    });

    test('C3 缺②：同会话存在 adopt 链路介入 → 不候选（计 adoptIntervened）', () {
      final report = aggregateChapterCompletionCandidates(
        events: [
          _independentCompletion(id: 'c1'),
          // 同会话的采纳链路 diff（messageId 透传形态）。
          _row(
            id: 'd-adopt',
            eventType: EditDiffEventTypes.diff,
            messageId: 'msg-1',
          ),
        ],
        goalWordsByChapter: {'ch1': 1000},
        wordCountByChapter: {'ch1': 1200},
      );
      expect(report.candidateCount, 0);
      expect(report.independentCompletionCount, 1);
      expect(report.adoptIntervenedCount, 1, reason: '采纳链路介入 → 排除留痕');
    });

    test('C4 缺③a：goalWords=0（未设目标）→ 不候选（计 noGoalTarget）', () {
      final report = aggregateChapterCompletionCandidates(
        events: [_independentCompletion(id: 'c1')],
        goalWordsByChapter: {'ch1': 0}, // 未设置
        wordCountByChapter: {'ch1': 1200},
      );
      expect(report.candidateCount, 0);
      expect(report.noGoalTargetCount, 1, reason: '未设目标 = 无「完整」定义，不替学员猜阈值');
      expect(report.adoptIntervenedCount, 0);
    });

    test('C4b 缺③a：goalWordsByChapter 缺省该章 → 视为 0，不候选', () {
      final report = aggregateChapterCompletionCandidates(
        events: [_independentCompletion(id: 'c1')],
        goalWordsByChapter: const {}, // 该章无记录
        wordCountByChapter: {'ch1': 1200},
      );
      expect(report.candidateCount, 0);
      expect(report.noGoalTargetCount, 1);
    });

    test('C5 缺③b：字数未达目标 → 不候选（计 belowGoal）', () {
      final report = aggregateChapterCompletionCandidates(
        events: [_independentCompletion(id: 'c1')],
        goalWordsByChapter: {'ch1': 1000},
        wordCountByChapter: {'ch1': 320}, // 未达
      );
      expect(report.candidateCount, 0);
      expect(report.belowGoalCount, 1);
    });

    test('C5b 字数恰等于目标 → 达标（>= 闭区间），产生候选', () {
      final report = aggregateChapterCompletionCandidates(
        events: [_independentCompletion(id: 'c1')],
        goalWordsByChapter: {'ch1': 1000},
        wordCountByChapter: {'ch1': 1000},
      );
      expect(report.candidateCount, 1);
      expect(report.belowGoalCount, 0);
    });

    test('C6 只记不判：候选/报告无任何成败判定布尔字段', () {
      final report = aggregateChapterCompletionCandidates(
        events: [_independentCompletion(id: 'c1')],
        goalWordsByChapter: {'ch1': 1000},
        wordCountByChapter: {'ch1': 1200},
      );
      final c = report.candidates.single as dynamic;
      // 不存在任何成败语义的字段（动态访问应抛 NoSuchMethodError）。
      expect(() => c.passed, throwsA(isA<NoSuchMethodError>()));
      expect(() => c.success, throwsA(isA<NoSuchMethodError>()));
      expect(() => c.reached, throwsA(isA<NoSuchMethodError>()));
      expect(() => c.completed, throwsA(isA<NoSuchMethodError>()));
      expect(() => c.improved, throwsA(isA<NoSuchMethodError>()));
      // 报告上不提供目标/达标布尔字段。
      final dynReport = report as dynamic;
      expect(() => dynReport.targetReached, throwsA(isA<NoSuchMethodError>()));
      expect(() => dynReport.isComplete, throwsA(isA<NoSuchMethodError>()));
    });

    test('C7 空事件列表 → 全零', () {
      final report = aggregateChapterCompletionCandidates(
        events: const [],
        goalWordsByChapter: const {},
        wordCountByChapter: const {},
      );
      expect(report.candidateCount, 0);
      expect(report.independentCompletionCount, 0);
      expect(report.adoptIntervenedCount, 0);
      expect(report.noGoalTargetCount, 0);
      expect(report.belowGoalCount, 0);
    });

    test('C8 adopt 两种形态都算介入：messageId 透传 / payload.source=adopt', () {
      // 形态一：messageId 非空。
      final m1 = aggregateChapterCompletionCandidates(
        events: [
          _independentCompletion(id: 'c1'),
          _row(id: 'd1', eventType: EditDiffEventTypes.diff, messageId: 'm-x'),
        ],
        goalWordsByChapter: {'ch1': 1000},
        wordCountByChapter: {'ch1': 1200},
      );
      expect(m1.candidateCount, 0);
      expect(m1.adoptIntervenedCount, 1);

      // 形态二：messageId=null 但 payload.source=adopt。
      final m2 = aggregateChapterCompletionCandidates(
        events: [
          _independentCompletion(id: 'c2'),
          _row(
            id: 'd2',
            eventType: EditDiffEventTypes.diff,
            payload: '{"diff_segments":1,"source":"adopt"}',
          ),
        ],
        goalWordsByChapter: {'ch1': 1000},
        wordCountByChapter: {'ch1': 1200},
      );
      expect(m2.candidateCount, 0);
      expect(m2.adoptIntervenedCount, 1);
    });

    test('C8b 同会话无 adopt、但另一会话有 adopt → 本会话仍自主（不串扰）', () {
      final report = aggregateChapterCompletionCandidates(
        events: [
          _independentCompletion(id: 'c1', sessionId: 's1'),
          // adopt diff 在另一会话 s2。
          _row(
            id: 'd2',
            eventType: EditDiffEventTypes.diff,
            sessionId: 's2',
            messageId: 'm-x',
          ),
        ],
        goalWordsByChapter: {'ch1': 1000},
        wordCountByChapter: {'ch1': 1200},
      );
      expect(report.candidateCount, 1, reason: 's1 无介入，不被 s2 的 adopt 污染');
      expect(report.adoptIntervenedCount, 0);
    });

    test('C9 completion.sessionId 为空串（未知会话）→ 按章节判定自主性', () {
      // sessionId=''（无法确定会话），且该章无 adopt diff → 仍候选。
      final clean = aggregateChapterCompletionCandidates(
        events: [_independentCompletion(id: 'c1', sessionId: '')],
        goalWordsByChapter: {'ch1': 1000},
        wordCountByChapter: {'ch1': 1200},
      );
      expect(clean.candidateCount, 1);
      expect(clean.candidates.single.sessionId, '');

      // sessionId=''，但该章有 adopt diff → 章节级介入，不候选。
      final dirty = aggregateChapterCompletionCandidates(
        events: [
          _independentCompletion(id: 'c1', sessionId: ''),
          _row(
            id: 'd1',
            eventType: EditDiffEventTypes.diff,
            sessionId: '',
            payload: '{"source":"adopt"}',
          ),
        ],
        goalWordsByChapter: {'ch1': 1000},
        wordCountByChapter: {'ch1': 1200},
      );
      expect(dirty.candidateCount, 0);
      expect(dirty.adoptIntervenedCount, 1);
    });
  });
}
