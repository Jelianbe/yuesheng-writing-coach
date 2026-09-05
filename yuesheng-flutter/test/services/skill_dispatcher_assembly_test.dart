// skill_dispatcher_assembly_test — buildSystemPromptV2 装配细节（R-019 批次七补测）
//
// 覆盖 teaching_capability_test 未锚定的两个分支：
//   1. L2 阶段裁切（contentForPhase：coaching-rhythm 在 P0 裁切、P2 完整）
//   2. attitude 档位注入（doubao 时 prompt 含态度声明）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('buildSystemPromptV2 装配细节', () {
    test('#A1 L2 阶段裁切：coaching-rhythm 在 P1 裁切与 P2 完整，注入内容不同', () {
      final p1 = SkillLoadContext(
        phase: TeachingPhase.p1World,
        attitude: AttitudeLevel.doubao,
        subphase: TeachingSubphase.diagnosis,
      );
      final p2 = SkillLoadContext(
        phase: TeachingPhase.p2PracticeLoop,
        attitude: AttitudeLevel.doubao,
        subphase: TeachingSubphase.diagnosis,
      );
      // P1/P2 均决议为 diagnosis mode（skill_layers.resolveL2Mode），
      // 两者都加载 coaching-rhythm——差异仅来自 contentForPhase 阶段裁切。
      final s1 = buildSystemPromptV2(p1).systemPrompt;
      final s2 = buildSystemPromptV2(p2).systemPrompt;
      expect(
        s1,
        isNot(equals(s2)),
        reason: 'P1 阶段 coaching-rhythm 应裁剪、P2 返回完整原文，注入内容须不同',
      );
    });

    test('#A2 attitude 档位注入：doubao 时 prompt 含态度档位声明', () {
      final r = buildSystemPromptV2(
        SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.doubao,
          subphase: TeachingSubphase.diagnosis,
        ),
      );
      expect(r.systemPrompt, contains('态度：豆包'));
    });
  });
}
