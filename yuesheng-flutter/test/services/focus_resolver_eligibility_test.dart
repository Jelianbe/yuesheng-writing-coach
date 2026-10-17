// ADR-0008 焦点资格闸护栏测试（T-20261017-01）
//
// 覆盖 §2.1 全部分支：
//   - 档 A（wordChoice）vs 档 B 低严重度：档 A 胜（X04 型修复方向）
//   - 档 B 获资格（L3 / confirmed）时 severity 语义保持
//   - 优先级 1（confirmed 池）不受资格闸约束
//   - 同档内 severity 语义不变（既有测试兼容性的根）
//   - 无标签症候按档 B
//   - reason 文案带资格标注（留痕可解释）
//
// 全部纯逻辑合成 fixture，零 DB / 零 LLM。

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/focus_resolver.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';
import 'package:writingcoach/types/teaching_types.dart';

FocusProblem _fp(
  String id,
  Severity severity,
  ConfirmationStatus confirmationStatus,
  String status, {
  int? confirmedAt,
}) => FocusProblem(
  syndromeId: id,
  syndromeName: 'name-$id',
  severity: severity,
  confirmationStatus: confirmationStatus,
  status: status,
  confirmedAt: confirmedAt,
);

ResolveFocusInput _input(
  List<FocusProblem> problems, {
  String? aiSuggestedFocusId,
  String? userFocusOverride,
  SkillLevel? studentSkillLevel,
}) => ResolveFocusInput(
  problems: problems,
  aiSuggestedFocusId: aiSuggestedFocusId,
  userFocusOverride: userFocusOverride,
  subphase: null,
  focusHistory: const [],
  studentSkillLevel: studentSkillLevel,
);

void main() {
  group('ADR-0008 资格闸 · 优先级 2（suspected）', () {
    test('X04 型：wordChoice L1 胜过 overwritten L2（闸前 0/6 的直接修复面）', () {
      // P018=wordChoice 档 A（L1）；P002=overwritten 档 B（L2，未获资格）
      final out = resolveTeachingFocus(
        _input([
          _fp('P002', Severity.l2, ConfirmationStatus.suspected, 'active'),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected, 'active'),
        ]),
      );
      expect(out.activatedFocusId, 'P018');
      expect(out.reason, contains('资格=直接教学'));
    });

    test('档 B 高严重度（L3）仍胜档 A L1（severity 语义对获资格者保持）', () {
      // P003=overwritten 档 B 但 L3 ⇒ 获资格 ⇒ severity 裁决 ⇒ L3 先
      final out = resolveTeachingFocus(
        _input([
          _fp('P003', Severity.l3, ConfirmationStatus.suspected, 'active'),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected, 'active'),
        ]),
      );
      expect(out.activatedFocusId, 'P003');
    });

    test('同档 B 内 severity 语义不变（L2 > L1）', () {
      // P002 / P001 均档 B ⇒ 回落 severity 次键（既有行为）
      final out = resolveTeachingFocus(
        _input([
          _fp('P001', Severity.l1, ConfirmationStatus.suspected, 'active'),
          _fp('P002', Severity.l2, ConfirmationStatus.suspected, 'active'),
        ]),
      );
      expect(out.activatedFocusId, 'P002');
    });

    test('同档 A 内 severity 语义不变（L2 翻译腔 > L1 基础语病）', () {
      // P018 / P032 均档 A（wordChoice）⇒ severity 次键
      final out = resolveTeachingFocus(
        _input([
          _fp('P018', Severity.l1, ConfirmationStatus.suspected, 'active'),
          _fp('P032', Severity.l2, ConfirmationStatus.suspected, 'active'),
        ]),
      );
      expect(out.activatedFocusId, 'P032');
    });

    test('无标签症候按档 B（不获无条件资格）', () {
      // P003=无 quantityTag ⇒ 档 B；P018 档 A ⇒ 闸生效
      final out = resolveTeachingFocus(
        _input([
          _fp('P003', Severity.l2, ConfirmationStatus.suspected, 'active'),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected, 'active'),
        ]),
      );
      expect(out.activatedFocusId, 'P018');
    });

    test('underwritten 档 B 不获无条件资格（P021 画感 L2 输给 P018 L1）', () {
      // X15 场景变体：若 GT 候选同为档 B 则不受影响；本例验档 A 抢位方向
      final out = resolveTeachingFocus(
        _input([
          _fp('P021', Severity.l2, ConfirmationStatus.suspected, 'active'),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected, 'active'),
        ]),
      );
      expect(out.activatedFocusId, 'P018');
    });
  });

  group('ADR-0008 资格闸 · 优先级 1（confirmed 池不受闸）', () {
    test('confirmed 池仍按 severity + confirmedAt（用户主权不受资格闸）', () {
      // P002 confirmed L2 vs P018 confirmed L1 ⇒ 池内 severity 语义原样
      final out = resolveTeachingFocus(
        _input([
          _fp(
            'P002',
            Severity.l2,
            ConfirmationStatus.confirmed,
            'active',
            confirmedAt: 100,
          ),
          _fp(
            'P018',
            Severity.l1,
            ConfirmationStatus.confirmed,
            'active',
            confirmedAt: 200,
          ),
        ]),
      );
      expect(out.activatedFocusId, 'P002');
      expect(out.reason, contains('优先级 1'));
    });
  });

  group('ADR-0008 资格闸 · 优先级 3（任意 active）', () {
    test('混合确认态下闸仍生效（P018 suspected vs P002 ignored→出池后剩者）', () {
      // P002 ignored ⇒ 出池；P018 suspected 仍在 ⇒ 优先级 2 命中 P018
      final out = resolveTeachingFocus(
        _input([
          _fp('P002', Severity.l2, ConfirmationStatus.ignored, 'active'),
          _fp('P018', Severity.l1, ConfirmationStatus.suspected, 'active'),
        ]),
      );
      expect(out.activatedFocusId, 'P018');
    });

    test('优先级 3 可达路径（全 active 无 confirmed/suspected 标注态）', () {
      // 注：ConfirmationStatus 含 dismissed 等态时会落到优先级 3
      final out = resolveTeachingFocus(
        _input([
          _fp('P002', Severity.l2, ConfirmationStatus.dismissed, 'active'),
          _fp('P018', Severity.l1, ConfirmationStatus.dismissed, 'active'),
        ]),
      );
      expect(out.activatedFocusId, 'P018');
      expect(out.reason, contains('优先级 3'));
    });
  });

  group('ADR-0008 资格闸 · 文案留痕', () {
    test('reason 含资格标注（直接教学）与严重度', () {
      final out = resolveTeachingFocus(
        _input([
          _fp('P018', Severity.l1, ConfirmationStatus.suspected, 'active'),
        ]),
      );
      expect(out.reason, contains('P018'));
      expect(out.reason, contains('severity=L1'));
      expect(out.reason, contains('资格=直接教学'));
    });

    test('档 B 胜出时 reason 标注「资格=条件」', () {
      final out = resolveTeachingFocus(
        _input([
          _fp('P002', Severity.l2, ConfirmationStatus.suspected, 'active'),
        ]),
      );
      expect(out.reason, contains('资格=条件'));
    });
  });
}
