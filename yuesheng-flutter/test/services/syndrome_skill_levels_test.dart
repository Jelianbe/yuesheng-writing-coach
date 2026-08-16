// ─────────────────────────────────────────────────────────────
// 批次60：症候技能层级 + 介入级别 + focus fallback 层级优先
// 依据：AI写作教学系统前置研究 V2.0 §2.1/§2.2
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/focus_resolver.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';
import 'package:writingcoach/services/training_input_builder.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('批次60a: 症候技能层级表', () {
    test('#S1 全部症候（注册表 ${kSyndromeRegistry.length} 个）有技能层级', () {
      expect(kSyndromeSkillLevels.length, kSyndromeRegistry.length);
      // 逐症候断言（b9 真源化：从注册表派生）
      for (final s in kSyndromeRegistry) {
        expect(skillLevelOf(s.id), s.level,
            reason: 'skillLevelOf(${s.id}) 应为 ${s.level.value}');
      }
      // 抽验分布
      expect(skillLevelOf('P003'), SkillLevel.l1); // 情绪标签化 → 基础表达
      expect(skillLevelOf('P006'), SkillLevel.l2); // 节奏停滞 → 叙事节奏
      expect(skillLevelOf('P009'), SkillLevel.l3); // 角色空心化 → 角色塑造
      expect(skillLevelOf('P013'), SkillLevel.l4); // 开篇无钩子 → 情节结构
      expect(skillLevelOf('P017'), SkillLevel.l4); // 伏笔失效 → 情节结构
      expect(skillLevelOf('P022'), SkillLevel.l1); // 重复用词/基础语病 → 基础表达（批次70）
      // 批次15（7.1）：P023-P027 网文商业症候 → 情节结构
      expect(skillLevelOf('P023'), SkillLevel.l4);
      expect(skillLevelOf('P024'), SkillLevel.l4);
      expect(skillLevelOf('P025'), SkillLevel.l4);
      expect(skillLevelOf('P026'), SkillLevel.l4);
      expect(skillLevelOf('P027'), SkillLevel.l4);
      // 批次23（叙事基础空缺）：P028 画面感缺失 → 叙事节奏
      expect(skillLevelOf('P028'), SkillLevel.l2);
      // 批次24（叙事基础空缺）：P029 段落失控 → 叙事节奏
      expect(skillLevelOf('P029'), SkillLevel.l2);
      // 批次25（叙事基础空缺）：P030 节奏比例失衡 → 情节结构
      expect(skillLevelOf('P030'), SkillLevel.l4);
      // 批次26（叙事基础空缺）：P031 设定矛盾 → 情节结构
      expect(skillLevelOf('P031'), SkillLevel.l4);
    });

    test('#S2 未知症候 → null', () {
      expect(skillLevelOf('P999'), isNull);
      expect(skillLevelOf(null), isNull);
      expect(skillLevelOf(''), isNull);
    });

    test('#S3 每层至少 3 个症候（层级分布合理）', () {
      final counts = <SkillLevel, int>{};
      for (final level in kSyndromeSkillLevels.values) {
        counts[level] = (counts[level] ?? 0) + 1;
      }
      expect(counts[SkillLevel.l1]! >= 3, isTrue);
      expect(counts[SkillLevel.l2]! >= 3, isTrue);
      expect(counts[SkillLevel.l3]! >= 3, isTrue);
      expect(counts[SkillLevel.l4]! >= 3, isTrue);
    });
  });

  group('批次60a: 学员当前技能层级映射', () {
    test('#S4 N0/N1 → L1（基础表达）', () {
      expect(skillLevelForBeginner(BeginnerLevel.n0Engage), SkillLevel.l1);
      expect(skillLevelForBeginner(BeginnerLevel.n1Elements), SkillLevel.l1);
    });

    test('#S5 N2 → L2 / N3 → L3 / N4 → L4', () {
      expect(skillLevelForBeginner(BeginnerLevel.n2Scene), SkillLevel.l2);
      expect(skillLevelForBeginner(BeginnerLevel.n3Diagnose), SkillLevel.l3);
      expect(skillLevelForBeginner(BeginnerLevel.n4Independent), SkillLevel.l4);
    });

    test('#S6 未定级 → null（不限制）', () {
      expect(skillLevelForBeginner(null), isNull);
    });
  });

  group('批次60b: 介入级别（逐步撤除脚手架）', () {
    test('#S7 0-1 次 → I do（示范+引导）', () {
      expect(interventionLevelForTrainingCount(0), InterventionLevel.iDo);
      expect(interventionLevelForTrainingCount(1), InterventionLevel.iDo);
    });

    test('#S8 2-3 次 → We do（标注+引导）', () {
      expect(interventionLevelForTrainingCount(2), InterventionLevel.weDo);
      expect(interventionLevelForTrainingCount(3), InterventionLevel.weDo);
    });

    test('#S9 ≥4 次 → You do（独立练习）', () {
      expect(interventionLevelForTrainingCount(4), InterventionLevel.youDo);
      expect(interventionLevelForTrainingCount(10), InterventionLevel.youDo);
    });
  });

  group('批次8 D3: 介入级别综合 severity/复发（回退脚手架）', () {
    test('#D1 复发（relapse）→ 强制 I do（即使已训练 ≥4 次）', () {
      expect(
        interventionLevelForTrainingCount(4, relapse: true),
        InterventionLevel.iDo,
      );
      expect(
        interventionLevelForTrainingCount(10, relapse: true),
        InterventionLevel.iDo,
      );
      expect(
        interventionLevelForTrainingCount(0, relapse: true),
        InterventionLevel.iDo,
      );
    });

    test('#D2 严重 L3 → 强制 I do（即使已训练 ≥4 次）', () {
      expect(
        interventionLevelForTrainingCount(4, currentSeverity: Severity.l3),
        InterventionLevel.iDo,
      );
      expect(
        interventionLevelForTrainingCount(10, currentSeverity: Severity.l3),
        InterventionLevel.iDo,
      );
    });

    test('#D3 L2/L1 不触发回退，维持次数分级', () {
      expect(
        interventionLevelForTrainingCount(4, currentSeverity: Severity.l2),
        InterventionLevel.youDo,
      );
      expect(
        interventionLevelForTrainingCount(2, currentSeverity: Severity.l1),
        InterventionLevel.weDo,
      );
      expect(
        interventionLevelForTrainingCount(1, currentSeverity: Severity.l2),
        InterventionLevel.iDo,
      );
    });

    test('#D4 不传 severity/relapse → 维持原纯次数行为', () {
      expect(interventionLevelForTrainingCount(0), InterventionLevel.iDo);
      expect(interventionLevelForTrainingCount(3), InterventionLevel.weDo);
      expect(interventionLevelForTrainingCount(5), InterventionLevel.youDo);
    });
  });

  group('批次16 7.2 performance_gate（介入级别加表现感知）', () {
    TrainingPerformance perf({
      required double passRate,
      int consecutivePasses = 0,
      int consecutiveFails = 0,
      required int totalCount,
    }) {
      return TrainingPerformance(
        passRate: passRate,
        consecutivePasses: consecutivePasses,
        consecutiveFails: consecutiveFails,
        totalCount: totalCount,
      );
    }

    test('#G1 连续 3 次未达标 → 强制 I do（即使已训练 ≥4 次）', () {
      final p = perf(passRate: 0, consecutiveFails: 3, totalCount: 4);
      expect(
        interventionLevelForTrainingCount(4, performance: p),
        InterventionLevel.iDo,
      );
      expect(
        interventionLevelForTrainingCount(10, performance: p),
        InterventionLevel.iDo,
      );
    });

    test('#G2 passRate < 0.5 且基础档位 We/You → 降一档', () {
      // 训练 4 次、1 次达标（passRate=0.25）→ You do 降 We do
      final p4 = perf(passRate: 0.25, totalCount: 4);
      expect(
        interventionLevelForTrainingCount(4, performance: p4),
        InterventionLevel.weDo,
      );
      // 训练 2 次、0 次达标（passRate=0）→ We do 降 I do
      final p2 = perf(passRate: 0, totalCount: 2);
      expect(
        interventionLevelForTrainingCount(2, performance: p2),
        InterventionLevel.iDo,
      );
    });

    test('#G3 连续 2 次未达标且基础档位 You do → 不升档（保持 We do）', () {
      final p = perf(passRate: 0.6, consecutiveFails: 2, totalCount: 5);
      expect(
        interventionLevelForTrainingCount(5, performance: p),
        InterventionLevel.weDo,
      );
    });

    test('#G4 首次训练即通过 → 提前升 We do', () {
      final p = perf(passRate: 1.0, consecutivePasses: 1, totalCount: 1);
      expect(
        interventionLevelForTrainingCount(1, performance: p),
        InterventionLevel.weDo,
      );
    });

    test('#G5 2-3 次全部通过 → 提前升 You do', () {
      final p2 = perf(passRate: 1.0, consecutivePasses: 2, totalCount: 2);
      expect(
        interventionLevelForTrainingCount(2, performance: p2),
        InterventionLevel.youDo,
      );
      final p3 = perf(passRate: 1.0, consecutivePasses: 3, totalCount: 3);
      expect(
        interventionLevelForTrainingCount(3, performance: p3),
        InterventionLevel.youDo,
      );
    });

    test('#G6 performance=null → 维持次数分级（回归）', () {
      expect(
        interventionLevelForTrainingCount(0, performance: null),
        InterventionLevel.iDo,
      );
      expect(
        interventionLevelForTrainingCount(3, performance: null),
        InterventionLevel.weDo,
      );
      expect(
        interventionLevelForTrainingCount(5, performance: null),
        InterventionLevel.youDo,
      );
    });

    test('#G7 D3 优先：L3 严重度 + 表现全优 → 仍 I do', () {
      final p = perf(passRate: 1.0, consecutivePasses: 3, totalCount: 3);
      expect(
        interventionLevelForTrainingCount(
          3,
          currentSeverity: Severity.l3,
          performance: p,
        ),
        InterventionLevel.iDo,
      );
    });

    test('#G8 延迟优先于提前：G1 与 G4 不冲突（连续未达标中不可能全通过，防御性）', () {
      // G1 触发时结果必为 I do，不受 G4 影响
      final p = perf(passRate: 0, consecutiveFails: 3, totalCount: 3);
      expect(
        interventionLevelForTrainingCount(1, performance: p),
        InterventionLevel.iDo,
      );
    });
  });

  group('批次60a: focus fallback 层级优先（软引导）', () {
    FocusProblem problem(
      String id, {
      Severity severity = Severity.l1,
      ConfirmationStatus status = ConfirmationStatus.confirmed,
    }) {
      return FocusProblem(
        syndromeId: id,
        syndromeName: '症候$id',
        severity: severity,
        confirmationStatus: status,
        status: 'active',
      );
    }

    ResolveFocusOutput resolve(
      List<FocusProblem> problems, {
      SkillLevel? studentLevel,
    }) {
      return resolveTeachingFocus(
        ResolveFocusInput(
          problems: problems,
          aiSuggestedFocusId: null, // 强制走 fallback
          userFocusOverride: null,
          subphase: null,
          focusHistory: const [],
          studentSkillLevel: studentLevel,
        ),
      );
    }

    test('#S10 无层级注入 → 按 severity 选最高（原行为）', () {
      // P013（L4 L1级？不：P013 是 L4）+ P003（L1）都 L1 严重度
      final out = resolve([
        problem('P003', severity: Severity.l1),
        problem('P013', severity: Severity.l2),
      ]);
      expect(out.activatedFocusId, 'P013'); // L2 severity 最高
    });

    test('#S11 学员 L1 → fallback 优先选层级≤L2 的症候（跳过越级）', () {
      final out = resolve([
        problem('P003', severity: Severity.l3), // L1 基础表达
        problem('P009', severity: Severity.l2), // L3 角色塑造（越级）
      ], studentLevel: SkillLevel.l1);
      // P003 虽严重度更低，但层级（L1 ≤ L1+1）合适 → 被优先
      expect(out.activatedFocusId, 'P003');
    });

    test('#S12 全部越级 → 回退 severity 最高（不硬拦截）', () {
      final out = resolve([
        problem('P012', severity: Severity.l1), // L4（越级）
        problem('P009', severity: Severity.l2), // L3（越级）
      ], studentLevel: SkillLevel.l1);
      // 全部越级 → 回退原逻辑，选 severity 最高的 P009
      expect(out.activatedFocusId, 'P009');
    });

    test('#S13 层级+1 以内含候选 → 在合适子集中按 severity 选', () {
      final out = resolve([
        problem('P006', severity: Severity.l1), // L2（≤ L1+1 合适）
        problem('P003', severity: Severity.l3), // L1（合适）
        problem('P015', severity: Severity.l3), // L4（越级）
      ], studentLevel: SkillLevel.l1);
      // 合适子集 {P006, P003} 中 severity 最高为 P003
      expect(out.activatedFocusId, 'P003');
    });
  });
}
