// ─────────────────────────────────────────────────────────────
// W-21-A 回归测试：诊断整合层契约 + A1 分组 + A4 未决收口
//
// 覆盖（设计稿 §二/§三）：
//   1. A1 分组：同 id 归组 / 跨章计数 / 同章高重叠归并（章节不重复计数、
//      引用不丢）/ 严重度峰值 / 证据池并集 / 时间首末
//   2. A4 收口：证据不足登记 / pending_context 透传 / 需人裁决透传
//   3. 快照：四契约容器（B 批占位恒空）/ 纯函数性
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_integration_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

DiagnosisEntryRef _e(
  String rowId,
  int idx,
  String id,
  Severity severity,
  List<String> evidence, {
  String chapter = 'ch-1',
  int at = 1000,
}) => DiagnosisEntryRef(
  rowId: rowId,
  entryIndex: idx,
  syndromeId: id,
  severity: severity,
  evidence: evidence,
  chapterId: chapter,
  createdAtSec: at,
);

void main() {
  group('A1 · buildDiagnosisGroups', () {
    test('同 syndrome_id 归组，不同 id 各自成组（组按 id 升序）', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P003', Severity.l2, ['x']),
        _e('r2', 0, 'P001', Severity.l1, ['y']),
        _e('r3', 1, 'P003', Severity.l1, ['z']),
      ]);
      expect(groups.map((g) => g.syndromeId).toList(), ['P001', 'P003']);
      expect(groups[1].memberRefs, ['r1#0', 'r3#1']);
    });

    test('跨章独立出现：chapterSpan 按章去重、chapterCount 可作系统性分母', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P001', Severity.l1, ['a'], chapter: 'ch-1', at: 100),
        _e('r2', 0, 'P001', Severity.l2, ['b'], chapter: 'ch-2', at: 200),
        _e('r3', 0, 'P001', Severity.l3, ['c'], chapter: 'ch-3', at: 300),
      ]);
      final g = groups.single;
      expect(g.chapterSpan, ['ch-1', 'ch-2', 'ch-3']);
      expect(g.chapterCount, 3);
      expect(g.severityMax, Severity.l3);
      expect(g.firstSeenSec, 100);
      expect(g.lastSeenSec, 300);
    });

    test('同章 + 证据重叠 ≥ 阈值 → 归并：章节不重复计数、引用不丢、dup 计数', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P001', Severity.l1, ['aaa', 'bbb'], chapter: 'ch-1'),
        _e('r1', 1, 'P001', Severity.l2, ['aaa', 'bbb'], chapter: 'ch-1'),
      ]);
      final g = groups.single;
      expect(g.memberRefs, ['r1#0', 'r1#1']); // 引用全保留
      expect(g.chapterSpan, ['ch-1']);
      expect(g.chapterCount, 1); // 章节不重复计数
      expect(g.duplicateMergedCount, 1);
      expect(g.severityMax, Severity.l2); // 峰值保留
    });

    test('同章但证据不相交 → 独立条目（章节仍只计一次）', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P001', Severity.l1, ['aaa'], chapter: 'ch-1'),
        _e('r1', 1, 'P001', Severity.l2, ['bbb'], chapter: 'ch-1'),
      ]);
      final g = groups.single;
      expect(g.duplicateMergedCount, 0);
      expect(g.memberRefs.length, 2);
      expect(g.evidencePool, ['aaa', 'bbb']);
    });

    test('证据池 = 并集去重排序', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P001', Severity.l1, ['bb', 'aa'], chapter: 'ch-1'),
        _e('r2', 0, 'P001', Severity.l1, ['aa', 'cc'], chapter: 'ch-2'),
      ]);
      expect(groups.single.evidencePool, ['aa', 'bb', 'cc']);
    });
  });

  group('A4 · collectUnresolvedQuestions', () {
    test('证据池为空的组 → insufficient_evidence 登记且阻塞引用=全部成员', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P001', Severity.l1, [], chapter: 'ch-1'),
        _e('r2', 0, 'P002', Severity.l1, ['e'], chapter: 'ch-1'),
      ]);
      final qs = collectUnresolvedQuestions(groups, nowSec: 500);
      expect(qs.length, 1);
      expect(qs.single.kind, UnresolvedQuestion.kindInsufficientEvidence);
      expect(qs.single.blockingRefs, ['r1#0']);
      expect(qs.single.resolvedAt, isNull);
    });

    test('pending_context 透传（W-15-B 接口）', () {
      final qs = collectUnresolvedQuestions(
        const [],
        pendingContexts: [
          UnresolvedSource('人物关系在后文才解释', ['r1#0']),
        ],
        nowSec: 500,
      );
      expect(qs.single.kind, UnresolvedQuestion.kindPendingContext);
      expect(qs.single.blockingRefs, ['r1#0']);
    });

    test('needs_human 透传 + 三类并存时全部登记（不静默丢弃）', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P001', Severity.l1, [], chapter: 'ch-1'),
      ]);
      final qs = collectUnresolvedQuestions(
        groups,
        pendingContexts: [UnresolvedSource('待补前文', [])],
        humanConflicts: [
          UnresolvedSource('P004/P017 互斥共现', ['r2#0']),
        ],
        nowSec: 500,
      );
      expect(qs.map((q) => q.kind).toSet(), {
        UnresolvedQuestion.kindPendingContext,
        UnresolvedQuestion.kindInsufficientEvidence,
        UnresolvedQuestion.kindNeedsHuman,
      });
      expect(qs.length, 3);
    });
  });

  group('buildIntegrationSnapshot', () {
    test('四契约容器：groups/questions 实装，hypotheses/candidates 恒空（B 批）', () {
      final snap = buildIntegrationSnapshot(
        entries: [
          _e('r1', 0, 'P001', Severity.l1, ['e']),
        ],
        nowSec: 500,
      );
      expect(snap.groups.length, 1);
      expect(snap.questions, isEmpty);
      expect(snap.hypotheses, isEmpty); // B 批
      expect(snap.candidates, isEmpty); // B 批
    });

    test('纯函数：同输入两次调用结果一致（确定性）', () {
      final entries = [
        _e('r1', 0, 'P001', Severity.l1, ['a'], chapter: 'ch-1', at: 100),
        _e('r2', 0, 'P001', Severity.l2, ['a'], chapter: 'ch-1', at: 200),
      ];
      final a = buildIntegrationSnapshot(entries: entries, nowSec: 500);
      final b = buildIntegrationSnapshot(entries: entries, nowSec: 500);
      expect(a.groups.single.memberRefs, b.groups.single.memberRefs);
      expect(a.groups.single.severityMax, b.groups.single.severityMax);
      expect(a.groups.single.chapterCount, b.groups.single.chapterCount);
    });
  });
}
