// ─────────────────────────────────────────────────────────────
// A3 intervention_value 先验护栏（T-20261018-04 第一批 · 设计批 2026-10-18 已批）
//
// 背景：单次链输出规范不产出 intervention_value ⇒ 240/240 格 iv 全 null ⇒
// 旧口径 valueScore 恒 0、total = severity + 1 恒等（ADR-0008 证据 4/6）。
// 新口径：iv null ⇒ 注册表 QuantityTag 先验（quantityPrior）；
//         iv 非空 ⇒ 既有 interventionValueRank 路径原样。
//
// 覆盖（设计批 §四 R5）：
//   1. 先验值逐标签断言：wordChoice = 3 / overwritten = 2 / underwritten = 2 / 无标签 = 2
//      （valueScore = 先验 + 1）
//   2. iv 非空路径原样不动（high/medium/low 三档）
//   3. 混合池排序确定性 + 同分 syndromeId 升序
//   4. rationale 诚实标注：「注册表先验」字样 + 无「未评定」残留
//   5. severity 三档 × 先验全交叉（分量独立性）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_integration_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

DiagnosisEntryRef _e(
  String id,
  Severity severity, {
  String chapter = 'ch-1',
  String? interventionValue,
}) => DiagnosisEntryRef(
  rowId: 'r1',
  entryIndex: 0,
  syndromeId: id,
  severity: severity,
  evidence: const ['e'],
  chapterId: chapter,
  createdAtSec: 1000,
  interventionValue: interventionValue,
);

void main() {
  group('A3 先验 · iv null 路径（T-20261018-04）', () {
    test('wordChoice（P018）= 3：与资格闸档 A 同一判断', () {
      final groups = buildDiagnosisGroups([
        _e('P018', Severity.l1), // 1 + 3 + 1 = 5（旧口径 2）
      ]);
      final c = buildTeachingFocusCandidates(groups, nowSec: 500).single;
      expect(c.scoreBreakdown['intervention_value'], 3);
      expect(c.scoreBreakdown['total'], 5);
      expect(c.rationale, contains('注册表先验'));
    });

    test('P032 同 wordChoice（翻译腔，判据同源）', () {
      final groups = buildDiagnosisGroups([_e('P032', Severity.l2)]);
      final c = buildTeachingFocusCandidates(groups, nowSec: 500).single;
      expect(c.scoreBreakdown['intervention_value'], 3); // 2+3+1=6
    });

    test('overwritten（P002）= 2', () {
      final groups = buildDiagnosisGroups([_e('P002', Severity.l1)]);
      final c = buildTeachingFocusCandidates(groups, nowSec: 500).single;
      expect(c.scoreBreakdown['intervention_value'], 2);
    });

    test('underwritten（P001）= 2', () {
      final groups = buildDiagnosisGroups([_e('P001', Severity.l1)]);
      final c = buildTeachingFocusCandidates(groups, nowSec: 500).single;
      expect(c.scoreBreakdown['intervention_value'], 2);
    });

    test('无标签症候 = 2（不区分的兜底）', () {
      // P003 视角漂移：注册表无 QuantityTag（ADR-0008 证据 7：无标签 14 条）
      final groups = buildDiagnosisGroups([_e('P003', Severity.l1)]);
      final c = buildTeachingFocusCandidates(groups, nowSec: 500).single;
      expect(c.scoreBreakdown['intervention_value'], 2);
    });

    test('rationale 无「未评定」残留（先验不伪装）', () {
      final groups = buildDiagnosisGroups([_e('P002', Severity.l2)]);
      final c = buildTeachingFocusCandidates(groups, nowSec: 500).single;
      expect(c.rationale, contains('注册表先验'));
      expect(c.rationale, isNot(contains('未评定')));
    });
  });

  group('A3 先验 · iv 非空路径原样（不回归）', () {
    for (final iv in ['high', 'medium', 'low']) {
      test('$iv ⇒ rank+1 原口径', () {
        final groups = buildDiagnosisGroups([
          _e('P002', Severity.l2, interventionValue: iv),
        ]);
        final c = buildTeachingFocusCandidates(groups, nowSec: 500).single;
        final expected = switch (iv) {
          'high' => 3,
          'medium' => 2,
          _ => 1,
        };
        expect(c.scoreBreakdown['intervention_value'], expected);
        expect(c.rationale, contains(iv));
        expect(c.rationale, isNot(contains('注册表先验')));
      });
    }
  });

  group('A3 先验 · 分量独立与排序确定性', () {
    test('severity 三档 × 先验全交叉：分量独立可加', () {
      for (final (sev, base) in [
        (Severity.l1, 1),
        (Severity.l2, 2),
        (Severity.l3, 3),
      ]) {
        final groups = buildDiagnosisGroups([
          _e('P002', sev), // overwritten 先验 ⇒ value 2
        ]);
        final c = buildTeachingFocusCandidates(groups, nowSec: 500).single;
        expect(c.scoreBreakdown['severity'], base);
        expect(c.scoreBreakdown['intervention_value'], 2);
        expect(c.scoreBreakdown['recurrence'], 1);
        expect(c.scoreBreakdown['total'], base + 3);
      }
    });

    test('混合池：iv 非空仍可压过先验（high=3 > wordChoice 先验 3 时同分按 id）', () {
      final groups = buildDiagnosisGroups([
        _e('P002', Severity.l1, interventionValue: 'high'), // 1+3+1=5
        _e('P018', Severity.l1), // wordChoice 先验：1+3+1=5
      ]);
      final cands = buildTeachingFocusCandidates(groups, nowSec: 500);
      // 同分 5 ⇒ syndromeId 升序：P002 < P018
      expect(cands.map((c) => c.syndromeId).toList(), ['P002', 'P018']);
    });

    test('恒等式选择性破坏：含 wordChoice 格 +1，其余格不变', () {
      // 旧口径全部格 total = severity + 1；新口径 wordChoice 格 = severity + 2
      final groups = buildDiagnosisGroups([
        _e('P018', Severity.l2), // 2 + 3 + 1 = 6（旧 4）
        _e('P002', Severity.l2), // 2 + 2 + 1 = 5（旧 4）
      ]);
      final byId = {
        for (final c in buildTeachingFocusCandidates(groups, nowSec: 500))
          c.syndromeId: c.scoreBreakdown['total'],
      };
      expect(byId['P018'], 6);
      expect(byId['P002'], 5);
    });
  });
}
