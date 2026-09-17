// ─────────────────────────────────────────────────────────────
// P2-10：三轴收束测试（buildProgressNarrative 纯函数 + GrowthOverview N 系）
// ─────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/focus_card_builder.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('P2-10 buildProgressNarrative：四轴收束', () {
    test('#N1 N 系优先于 P 系（教学起点坐标）', () {
      final n = buildProgressNarrative(
        phase: TeachingPhase.p3Training,
        beginnerLevel: BeginnerLevel.n2Scene,
        focusName: '节奏失衡',
        skillLevel: SkillLevel.l2,
        intervention: InterventionLevel.weDo,
      );
      expect(n, contains('N2 场景构建'));
      expect(n, isNot(contains('P3 深度训练')));
      expect(n, contains('L2 叙事节奏'));
      expect(n, contains('下一步'));
    });

    test('#N2 无 N 系 → 回退 P 系', () {
      final p = buildProgressNarrative(
        phase: TeachingPhase.p4Review,
        beginnerLevel: null,
        focusName: '声线漂移',
        skillLevel: SkillLevel.l5,
        intervention: InterventionLevel.youDo,
      );
      expect(p, contains('P4 毕业复核'));
      expect(p, contains('L5 风格声线'));
      expect(p, contains('声线漂移'));
    });

    test('#N3 双坐标都缺 → 只报焦点（不编造坐标）', () {
      final x = buildProgressNarrative(
        phase: null,
        beginnerLevel: null,
        focusName: '目标模糊',
        skillLevel: SkillLevel.l1,
        intervention: InterventionLevel.iDo,
      );
      expect(x, contains('当前阶段未知'));
      expect(x, contains('目标模糊'));
    });

    test('#N4 纯展示不评判（无「你应该/必须」句式）', () {
      final n = buildProgressNarrative(
        phase: TeachingPhase.p2PracticeLoop,
        beginnerLevel: BeginnerLevel.n3Diagnose,
        focusName: '主角被动',
        skillLevel: SkillLevel.l3,
        intervention: InterventionLevel.youDo,
      );
      expect(n.contains('应该'), isFalse);
      expect(n.contains('必须'), isFalse);
    });
  });
}
