// ─────────────────────────────────────────────────────────────
// 契约测试 — 教学能力
//
// 验证 TeachingCapability 接口可被现有实现 TeachingCapabilityImpl 满足
//（编译期 implements 断言 + 实例方法行为校验，天然规避同名方法自递归）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/capability_registry.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/skill_layers.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('TeachingCapability 契约', () {
    test('接口在注册表中注册', () {
      expect(
        CapabilityContractRegistry.contractTypes,
        contains(TeachingCapability),
      );
    });

    test('TeachingCapabilityImpl 满足契约（编译期 implements 断言 + 行为）', () {
      final impl = TeachingCapabilityImpl();
      expect(impl, isA<TeachingCapability>());

      // buildSystemPrompt：经契约实例方法消费，委托到 buildSystemPromptV2
      final ctx = SkillLoadContext(
        phase: TeachingPhase.p2PracticeLoop,
        attitude: AttitudeLevel.doubao,
        subphase: TeachingSubphase.diagnosis,
      );
      final result = impl.buildSystemPrompt(ctx);
      expect(result, isA<SystemPromptResult>());
      expect(result.systemPrompt, isNotEmpty);
      expect(result.estimatedTokens, greaterThan(0));
      expect(result.l2Mode, L2Mode.diagnosis);

      // resolveL2Mode：经 _resolveL2ModeImpl 别名委托顶层函数，不自递归
      final mode = impl.resolveL2Mode(ctx);
      expect(mode, isA<L2Mode>());
      expect(mode, L2Mode.diagnosis);
    });

    test('顶层纯函数行为（向后兼容）', () {
      final ctx = SkillLoadContext(
        phase: TeachingPhase.p2PracticeLoop,
        attitude: AttitudeLevel.doubao,
        subphase: TeachingSubphase.diagnosis,
      );
      final result = buildSystemPromptV2(ctx);
      expect(result, isA<SystemPromptResult>());
      expect(result.systemPrompt, isNotEmpty);
      expect(result.estimatedTokens, greaterThan(0));

      final mode = resolveL2Mode(ctx);
      expect(mode, isA<L2Mode>());
      expect(mode, L2Mode.diagnosis);
    });
  });
}
