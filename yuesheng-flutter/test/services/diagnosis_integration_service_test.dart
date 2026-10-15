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
  String? interventionValue,
}) => DiagnosisEntryRef(
  rowId: rowId,
  entryIndex: idx,
  syndromeId: id,
  severity: severity,
  evidence: evidence,
  chapterId: chapter,
  createdAtSec: at,
  interventionValue: interventionValue,
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
    test('单章单条：组 1 · 无假设 · 候选 1 · 无未决', () {
      final snap = buildIntegrationSnapshot(
        entries: [
          _e('r1', 0, 'P001', Severity.l1, ['e']),
        ],
        nowSec: 500,
      );
      expect(snap.groups.length, 1);
      expect(snap.questions, isEmpty);
      expect(snap.hypotheses, isEmpty); // 单章不触发 systematic
      expect(snap.candidates.length, 1); // B 批起恒有候选（不决定，仅排序）
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

  group('A2 · buildGlobalHypotheses', () {
    test('跨 ≥3 章独立出现 → systematic 假设（statement 模板 + 规则可追溯）', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P001', Severity.l1, ['a'], chapter: 'ch-1'),
        _e('r2', 0, 'P001', Severity.l2, ['b'], chapter: 'ch-2'),
        _e('r3', 0, 'P001', Severity.l2, ['c'], chapter: 'ch-3'),
      ]);
      final hs = buildGlobalHypotheses(groups, nowSec: 500);
      expect(hs.length, 1);
      expect(hs.single.kind, 'systematic');
      expect(hs.single.statement, contains('3 个章节'));
      expect(hs.single.statement, contains('P001'));
      expect(hs.single.ruleId, 'R-A2-systematic-n3');
      expect(hs.single.status, 'active');
    });

    test('仅 2 章 → 不触发（阈值初值 N=3）', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P001', Severity.l1, ['a'], chapter: 'ch-1'),
        _e('r2', 0, 'P001', Severity.l1, ['b'], chapter: 'ch-2'),
      ]);
      expect(buildGlobalHypotheses(groups, nowSec: 500), isEmpty);
    });

    test('互斥对两组同时存在 → structural 假设（复用 validator 真源）', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P004', Severity.l2, ['a'], chapter: 'ch-1'),
        _e('r2', 0, 'P017', Severity.l2, ['b'], chapter: 'ch-1'),
      ]);
      final hs = buildGlobalHypotheses(groups, nowSec: 500);
      expect(hs.single.kind, 'structural');
      expect(hs.single.statement, contains('P004/P017'));
      expect(hs.single.ruleId, 'R-A2-structural-mutex');
    });

    test('无假设条件 → 空列表', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P001', Severity.l1, ['a'], chapter: 'ch-1'),
        _e('r2', 0, 'P002', Severity.l1, ['b'], chapter: 'ch-1'),
      ]);
      expect(buildGlobalHypotheses(groups, nowSec: 500), isEmpty);
    });
  });

  group('A3 · buildTeachingFocusCandidates', () {
    test('评分分解各分量独立可解释，等权求和', () {
      // L2 + high(3) + 1 章 = 2+3+1 = 6
      final groups = buildDiagnosisGroups([
        _e(
          'r1',
          0,
          'P001',
          Severity.l2,
          ['a'],
          chapter: 'ch-1',
          interventionValue: 'high',
        ),
      ]);
      final c = buildTeachingFocusCandidates(groups, nowSec: 500).single;
      expect(c.scoreBreakdown['severity'], 2);
      expect(c.scoreBreakdown['intervention_value'], 3);
      expect(c.scoreBreakdown['recurrence'], 1);
      expect(c.scoreBreakdown['total'], 6);
      expect(c.rationale, contains('P001'));
      expect(c.rationale, contains('high'));
      expect(c.status, 'proposed'); // 只出候选，不决定
    });

    test('null 干预价值 = 0 分（未评定不加分）', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P001', Severity.l1, ['a'], chapter: 'ch-1'),
      ]);
      final c = buildTeachingFocusCandidates(groups, nowSec: 500).single;
      expect(c.scoreBreakdown['intervention_value'], 0);
      expect(c.rationale, contains('未评定'));
    });

    test('排序：total 降序，同分按 syndromeId 升序（确定性）', () {
      final groups = buildDiagnosisGroups([
        _e('r1', 0, 'P002', Severity.l1, ['a'], chapter: 'ch-1'), // 1+0+1=2
        _e(
          'r2',
          0,
          'P001',
          Severity.l3,
          ['b'],
          chapter: 'ch-1',
          interventionValue: 'high', // 3+3+1=7
        ),
        _e('r3', 0, 'P003', Severity.l1, ['c'], chapter: 'ch-1'), // 1+0+1=2
      ]);
      final cands = buildTeachingFocusCandidates(groups, nowSec: 500);
      expect(cands.map((c) => c.syndromeId).toList(), ['P001', 'P002', 'P003']);
    });

    test('recurrence 分量封顶 = 系统性阈值（防长篇单症候无界膨胀）', () {
      final entries = [
        for (var i = 1; i <= 6; i++)
          _e('r$i', 0, 'P001', Severity.l1, ['e-$i'], chapter: 'ch-$i'),
      ];
      final groups = buildDiagnosisGroups(entries);
      final c = buildTeachingFocusCandidates(groups, nowSec: 500).single;
      expect(c.scoreBreakdown['recurrence'], kSystematicChapterThreshold);
    });
  });

  group('B 批快照填充', () {
    test('快照的 hypotheses/candidates 已实装（与独立函数一致）', () {
      final snap = buildIntegrationSnapshot(
        entries: [
          _e('r1', 0, 'P001', Severity.l1, ['a'], chapter: 'ch-1'),
          _e('r2', 0, 'P001', Severity.l2, ['b'], chapter: 'ch-2'),
          _e('r3', 0, 'P001', Severity.l1, ['c'], chapter: 'ch-3'),
        ],
        nowSec: 500,
      );
      expect(snap.hypotheses.single.kind, 'systematic');
      expect(snap.candidates.single.syndromeId, 'P001');
      expect(
        snap.candidates.single.scoreBreakdown['recurrence'],
        kSystematicChapterThreshold,
      );
    });

    test('组级干预价值取最高档（组内多条不同档位）', () {
      final snap = buildIntegrationSnapshot(
        entries: [
          _e(
            'r1',
            0,
            'P001',
            Severity.l1,
            ['a'],
            chapter: 'ch-1',
            interventionValue: 'low',
          ),
          _e(
            'r2',
            0,
            'P001',
            Severity.l2,
            ['b'],
            chapter: 'ch-1',
            interventionValue: 'medium',
          ),
        ],
        nowSec: 500,
      );
      expect(snap.groups.single.interventionValueMax, 'medium');
    });
  });
}
