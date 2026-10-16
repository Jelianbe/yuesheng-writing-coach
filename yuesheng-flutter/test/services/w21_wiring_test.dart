// ─────────────────────────────────────────────────────────────
// W-21 接线清偿护栏（2026-10-16）
//
// 背景：W-21 阶段一的四契约产物曾「产出即弃」——`_runIntegrationObserver`
//   对纯函数快照算完即弃（可证明空转 + 与候选提取双算）；A4 ①类输入
//   （W-15-B pending_context）从未传入；A2/A4 产物零消费方（违反设计稿
//   A4「禁止静默丢弃」原则）。本批清偿后，四个纯函数是本批改动的可判
//   红界面：
//   ① buildPendingContextSources —— A4 ①输入合成（标记→未决源）
//   ② formatIntegrationProbeSummary —— A2/A4 档 A 探针摘要（调试态可见）
//   ③ toFocusCandidateCards —— A3 候选→DTO 映射（名称回退口径）
//   ④ 快照端到端 —— 合成源经 buildIntegrationSnapshot 落 kindPendingContext
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_integration_service.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

Syndrome _syndrome(
  String id, {
  bool? pendingContext,
  Severity severity = Severity.l2,
}) {
  return Syndrome(
    syndromeId: id,
    name: '症候 $id',
    severity: severity,
    evidence: const ['证据一'],
    explanation: '解释',
    pendingContext: pendingContext,
  );
}

DiagnosisEntryRef _entry(String syndromeId, {String chapter = 'ch-1'}) {
  return DiagnosisEntryRef(
    rowId: 'msg-1',
    entryIndex: 0,
    syndromeId: syndromeId,
    severity: Severity.l2,
    evidence: const ['证据一'],
    chapterId: chapter,
    createdAtSec: 1000,
  );
}

GlobalHypothesis _hypothesis() {
  return const GlobalHypothesis(
    hypothesisId: 'gh-1',
    kind: 'systematic',
    statement: '症候 P001 已在 3 个章节独立出现',
    sourceGroupIds: ['dg-P001'],
    ruleId: 'R-A2-systematic-n3',
    status: 'active',
  );
}

UnresolvedQuestion _question(String statement) {
  return UnresolvedQuestion(
    questionId: 'uq-1',
    kind: UnresolvedQuestion.kindInsufficientEvidence,
    statement: statement,
    blockingRefs: const ['msg-1#0'],
    createdAtSec: 1000,
  );
}

void main() {
  group('① buildPendingContextSources（A4 ①输入合成）', () {
    test('仅 pendingContext=true 产源；引用 = messageId#index', () {
      final sources = buildPendingContextSources(
        syndromes: [
          _syndrome('P001', pendingContext: true),
          _syndrome('P002', pendingContext: false),
          _syndrome('P003'), // null
          _syndrome('P004', pendingContext: true),
        ],
        messageId: 'msg-7',
      );
      expect(sources.length, 2);
      expect(sources[0].statement, contains('P001'));
      expect(sources[0].statement, contains('pending_context'));
      expect(sources[0].blockingRefs, ['msg-7#0']);
      expect(sources[1].blockingRefs, ['msg-7#3']);
    });

    test('零标记（全 false/null）⇒ 空列表', () {
      expect(
        buildPendingContextSources(
          syndromes: [
            _syndrome('P001'),
            _syndrome('P002', pendingContext: false),
          ],
          messageId: 'm',
        ),
        isEmpty,
      );
    });
  });

  group('④ 快照端到端（合成源 → questions）', () {
    test('pending 源经 buildIntegrationSnapshot 转 kindPendingContext', () {
      final snapshot = buildIntegrationSnapshot(
        entries: [_entry('P001')],
        pendingContexts: buildPendingContextSources(
          syndromes: [_syndrome('P001', pendingContext: true)],
          messageId: 'msg-9',
        ),
        nowSec: 1000,
      );
      final pending = snapshot.questions
          .where((e) => e.kind == UnresolvedQuestion.kindPendingContext)
          .toList();
      expect(pending.length, 1);
      expect(pending.single.blockingRefs, ['msg-9#0']);
    });

    test('无标记轮次 ⇒ 无 pending 类未决（不私造）', () {
      final snapshot = buildIntegrationSnapshot(
        entries: [_entry('P001')],
        nowSec: 1000,
      );
      expect(
        snapshot.questions.where(
          (e) => e.kind == UnresolvedQuestion.kindPendingContext,
        ),
        isEmpty,
      );
    });
  });

  group('② formatIntegrationProbeSummary（A2/A4 档 A 探针）', () {
    test('两罐皆空 ⇒ 空串（调用方不打日志）', () {
      expect(
        formatIntegrationProbeSummary(
          const IntegrationSnapshot(
            groups: [],
            hypotheses: [],
            candidates: [],
            questions: [],
          ),
        ),
        '',
      );
    });

    test('有产物 ⇒ 计数与摘要在场；长 statement 截断', () {
      final summary = formatIntegrationProbeSummary(
        IntegrationSnapshot(
          groups: const [],
          hypotheses: [_hypothesis()],
          candidates: const [],
          questions: [_question('症' * 100)],
        ),
      );
      expect(summary, contains('假设 1'));
      expect(summary, contains('未决 1'));
      expect(summary, contains('insufficient_evidence'));
      expect(summary.length, lessThan(200)); // 截断生效
      expect(summary, isNot(contains('症' * 100)));
    });
  });

  group('③ toFocusCandidateCards（A3 候选→DTO 映射）', () {
    test('注册表无记录 ⇒ 名称回退 syndromeId 原文', () {
      final cards = toFocusCandidateCards([
        const TeachingFocusCandidate(
          candidateId: 'c-1',
          syndromeId: 'P999',
          groupId: 'dg-P999',
          scoreBreakdown: {'total': 7, 'severity': 3},
          rationale: '评分分解：严重度 3 × 干预 2',
          status: 'proposed',
        ),
      ]);
      expect(cards.single.syndromeId, 'P999');
      expect(cards.single.name, 'P999');
      expect(cards.single.total, 7);
      expect(cards.single.rationale, contains('评分分解'));
    });

    test('注册表有记录 ⇒ 用注册名（P001 在册）', () {
      final cards = toFocusCandidateCards([
        const TeachingFocusCandidate(
          candidateId: 'c-2',
          syndromeId: 'P001',
          groupId: 'dg-P001',
          scoreBreakdown: {'total': 5},
          rationale: 'r',
          status: 'proposed',
        ),
      ]);
      expect(cards.single.name, isNot('P001'));
      expect(cards.single.name, isNotEmpty);
    });

    test('空候选 ⇒ 空列表（调用方据此不渲染候选区）', () {
      expect(toFocusCandidateCards(const []), isEmpty);
    });
  });
}
