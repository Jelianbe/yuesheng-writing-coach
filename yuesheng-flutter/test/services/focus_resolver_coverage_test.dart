// T2-5 (X-028-COV) focus_resolver.dart 覆盖率补测
//
// 该模块为纯逻辑（不依赖 DB/LLM），枚举输入组合即可覆盖全部可达分支。
// 目标：focus_resolver.dart 行覆盖率 ≥ 85%。
//
// 已知逻辑死代码（测试不可达，已排除）：
//   - _selectFallback 优先级3「任意 active」（L174-181）：候选池只含 confirmed/suspected，
//     优先级1/2 必中其一，优先级3 永远不可达。

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/services/focus_resolver.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 构造一个活跃症候视图
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

/// 便捷构造 resolver 输入
ResolveFocusInput _input({
  required List<FocusProblem> problems,
  String? aiSuggestedFocusId,
  String? userFocusOverride,
  TeachingSubphase? subphase,
  List<FocusHistoryEntry> focusHistory = const [],
  SkillLevel? studentSkillLevel,
}) => ResolveFocusInput(
  problems: problems,
  aiSuggestedFocusId: aiSuggestedFocusId,
  userFocusOverride: userFocusOverride,
  subphase: subphase,
  focusHistory: focusHistory,
  studentSkillLevel: studentSkillLevel,
);

void main() {
  // ── 主路径：6 项校验通过 ──
  group('主路径通过', () {
    test('AI 建议 focus 在池中且 active → 通过（aiSuggested）', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'active'),
          ],
          aiSuggestedFocusId: 'P003',
        ),
      );
      expect(out.source, FocusSource.aiSuggested);
      expect(out.activatedFocusId, 'P003');
    });

    test('用户覆盖 focus 在池中且 active → 通过（userOverride）', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'active'),
          ],
          userFocusOverride: 'P003',
        ),
      );
      expect(out.source, FocusSource.userOverride);
      expect(out.activatedFocusId, 'P003');
    });
  });

  // ── 无候选 → fallback ──
  group('无候选 fallback', () {
    test('活跃症候列表为空 → none（不注入 L3）', () {
      final out = resolveTeachingFocus(
        _input(
          problems: const [],
          aiSuggestedFocusId: null,
          userFocusOverride: null,
        ),
      );
      expect(out.source, FocusSource.none);
      expect(out.activatedFocusId, isNull);
      expect(out.reason, contains('活跃症候列表为空'));
    });

    test('全部 rejected/resolved → 无可用 active → none', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.rejected, 'active'),
            _fp('P004', Severity.l2, ConfirmationStatus.suspected, 'resolved'),
          ],
          aiSuggestedFocusId: null,
          userFocusOverride: null,
        ),
      );
      expect(out.source, FocusSource.none);
      expect(out.activatedFocusId, isNull);
      expect(out.reason, contains('无可用 active 症候'));
    });

    test('fallback 优先级1（confirmed）按 severity + 层级引导选 L1', () {
      // P003=L1(基础表达), P005=L4(情节结构)；学员 L1 → 优先层级≤当前+1=L2
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp(
              'P003',
              Severity.l3,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 100,
            ),
            _fp(
              'P005',
              Severity.l2,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 200,
            ),
          ],
          studentSkillLevel: SkillLevel.l1,
        ),
      );
      expect(out.source, FocusSource.fallback);
      expect(out.activatedFocusId, 'P003'); // L1 优先于 L4
    });

    test('fallback 优先级1 全部越级 → 回退全候选选最高 severity', () {
      // P005=L4, P009=L3；学员 L1(maxLevel=2) 全越级 → 回退 sorted.first（severity 降序）
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp(
              'P005',
              Severity.l2,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 100,
            ),
            _fp(
              'P009',
              Severity.l3,
              ConfirmationStatus.confirmed,
              'active',
              confirmedAt: 200,
            ),
          ],
          studentSkillLevel: SkillLevel.l1,
        ),
      );
      expect(out.source, FocusSource.fallback);
      expect(out.activatedFocusId, 'P009'); // l3 在 l2 之前
    });

    test('fallback 优先级2（suspected）', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.suspected, 'active'),
            _fp('P004', Severity.l2, ConfirmationStatus.suspected, 'active'),
          ],
          studentSkillLevel: SkillLevel.l1,
        ),
      );
      expect(out.source, FocusSource.fallback);
      expect(out.activatedFocusId, 'P003');
    });
  });

  // ── 候选不在池中 ──
  group('候选不在池中', () {
    test('非训练中 + 候选不在池 → fallback（不在池中）', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.suspected, 'active'),
          ],
          aiSuggestedFocusId: 'PX99',
          subphase: TeachingSubphase.diagnosis,
        ),
      );
      expect(out.source, FocusSource.fallback);
      expect(out.reason, contains('不在 active_problem 池中'));
    });

    test('训练中 + 用户切换 + 候选不在池 + 原 focus 有效 → 维持原 focus', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'active'),
            _fp('P002', Severity.l2, ConfirmationStatus.confirmed, 'active'),
          ],
          userFocusOverride: 'PX99',
          subphase: TeachingSubphase.practice,
          focusHistory: [FocusHistoryEntry(focusId: 'P002', timestamp: 1)],
        ),
      );
      expect(out.source, FocusSource.aiSuggested);
      expect(out.activatedFocusId, 'P002');
      expect(out.reason, contains('维持原 focus'));
    });

    test('训练中 + AI 建议候选不在池 + 原 focus 有效 → fallback（不维持）', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'active'),
            _fp('P002', Severity.l2, ConfirmationStatus.confirmed, 'active'),
          ],
          aiSuggestedFocusId: 'PX99',
          subphase: TeachingSubphase.practice,
          focusHistory: [FocusHistoryEntry(focusId: 'P002', timestamp: 1)],
        ),
      );
      expect(out.source, FocusSource.fallback);
      expect(out.reason, contains('不在 active_problem 池中'));
    });
  });

  // ── 候选被 rejected / resolved ──
  group('候选 rejected / resolved', () {
    test('候选 rejected + 非训练中 → fallback（无可用 → none）', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.rejected, 'active'),
          ],
          aiSuggestedFocusId: 'P003',
          subphase: TeachingSubphase.diagnosis,
        ),
      );
      expect(out.source, FocusSource.none);
      expect(out.reason, contains('已被 rejected'));
    });

    test('候选 resolved + 非训练中 → fallback（无可用 → none）', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'resolved'),
          ],
          aiSuggestedFocusId: 'P003',
          subphase: TeachingSubphase.diagnosis,
        ),
      );
      expect(out.source, FocusSource.none);
      expect(out.reason, contains('已 resolved'));
    });

    test('候选 resolved + 训练中 + 用户切换 + 原 focus 有效 → 维持原 focus', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'resolved'),
            _fp('P002', Severity.l2, ConfirmationStatus.confirmed, 'active'),
          ],
          userFocusOverride: 'P003',
          subphase: TeachingSubphase.practice,
          focusHistory: [FocusHistoryEntry(focusId: 'P002', timestamp: 1)],
        ),
      );
      expect(out.source, FocusSource.aiSuggested);
      expect(out.activatedFocusId, 'P002');
      expect(out.rejectReason, contains('已解决'));
    });
  });

  // ── 训练中冲突解决（5.7.2）──
  group('训练中冲突解决', () {
    test('训练中 + 用户主动切换（有效）→ 允许切换', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'active'),
          ],
          userFocusOverride: 'P003',
          subphase: TeachingSubphase.practice,
        ),
      );
      expect(out.source, FocusSource.userOverride);
      expect(out.activatedFocusId, 'P003');
      expect(out.rejectReason, contains('已按你的要求切换'));
    });

    test('训练中 + AI 自主切换 + 原 focus 有效 → 拒绝维持原 focus', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'active'),
            _fp('P002', Severity.l2, ConfirmationStatus.confirmed, 'active'),
          ],
          aiSuggestedFocusId: 'P003',
          subphase: TeachingSubphase.practice,
          focusHistory: [FocusHistoryEntry(focusId: 'P002', timestamp: 1)],
        ),
      );
      expect(out.source, FocusSource.aiSuggested);
      expect(out.activatedFocusId, 'P002');
      expect(out.reason, contains('拒绝 AI 自主切换'));
    });

    test('训练中 + AI 自主切换 + 原 focus 无效 → fallback', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'active'),
          ],
          aiSuggestedFocusId: 'P003',
          subphase: TeachingSubphase.practice,
          focusHistory: [FocusHistoryEntry(focusId: 'P999', timestamp: 1)],
        ),
      );
      expect(out.source, FocusSource.fallback);
      expect(out.activatedFocusId, 'P003');
    });
  });

  // ── 频繁切换检测（5.7.3）──
  group('频繁切换检测', () {
    test('频繁切换 + 原 focus 有效 → 维持原 focus', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'active'),
            _fp('P002', Severity.l2, ConfirmationStatus.confirmed, 'active'),
          ],
          aiSuggestedFocusId: 'P003',
          subphase: TeachingSubphase.diagnosis,
          focusHistory: [
            FocusHistoryEntry(focusId: 'P002', timestamp: 1),
            FocusHistoryEntry(focusId: 'P005', timestamp: 2),
            FocusHistoryEntry(focusId: 'P009', timestamp: 3),
          ],
        ),
      );
      expect(out.source, FocusSource.aiSuggested);
      expect(out.activatedFocusId, 'P002');
      expect(out.reason, contains('频繁切换检测'));
    });

    test('频繁切换 + 原 focus 无效 → 采用候选 focus', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'active'),
          ],
          aiSuggestedFocusId: 'P003',
          subphase: TeachingSubphase.diagnosis,
          focusHistory: [
            FocusHistoryEntry(focusId: 'P002', timestamp: 1),
            FocusHistoryEntry(focusId: 'P005', timestamp: 2),
            FocusHistoryEntry(focusId: 'P009', timestamp: 3),
          ],
        ),
      );
      expect(out.source, FocusSource.aiSuggested);
      expect(out.activatedFocusId, 'P003');
      expect(out.reason, contains('原 focus 无效，采用候选'));
    });

    test('_isFrequentSwitching：candidate == 最近一轮 → 不触发降级', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'active'),
          ],
          aiSuggestedFocusId: 'P003',
          subphase: TeachingSubphase.diagnosis,
          focusHistory: [
            FocusHistoryEntry(focusId: 'P003', timestamp: 1),
            FocusHistoryEntry(focusId: 'P005', timestamp: 2),
            FocusHistoryEntry(focusId: 'P009', timestamp: 3),
          ],
        ),
      );
      // candidate == recent.first → 不降级 → 通过校验
      expect(out.source, FocusSource.aiSuggested);
      expect(out.activatedFocusId, 'P003');
    });

    test('_isFrequentSwitching：历史不足阈值 → 不触发降级', () {
      final out = resolveTeachingFocus(
        _input(
          problems: [
            _fp('P003', Severity.l3, ConfirmationStatus.confirmed, 'active'),
          ],
          aiSuggestedFocusId: 'P003',
          subphase: TeachingSubphase.diagnosis,
          focusHistory: [FocusHistoryEntry(focusId: 'P003', timestamp: 1)],
        ),
      );
      expect(out.source, FocusSource.aiSuggested);
      expect(out.activatedFocusId, 'P003');
    });
  });

  // ── 辅助函数直接验证 ──
  group('辅助函数', () {
    test('isInTraining：practice/feedback 为训练中', () {
      expect(isInTraining(TeachingSubphase.practice), isTrue);
      expect(isInTraining(TeachingSubphase.feedback), isTrue);
      expect(isInTraining(TeachingSubphase.diagnosis), isFalse);
      expect(isInTraining(null), isFalse);
    });

    test('FocusSwitch.threshold 常量存在', () {
      expect(FocusSwitch.threshold, greaterThanOrEqualTo(2));
    });
  });
}
