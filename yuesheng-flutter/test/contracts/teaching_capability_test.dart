// ─────────────────────────────────────────────────────────────
// 契约测试 — 教学能力
//
// 验证 TeachingCapability 接口可被现有实现满足。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/teaching_capability.dart';
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

    test('buildSystemPrompt 返回 SystemPromptResult', () {
      final ctx = SkillLoadContext(
        phase: TeachingPhase.p2PracticeLoop,
        attitude: AttitudeLevel.doubao,
        subphase: TeachingSubphase.diagnosis,
      );
      final result = buildSystemPromptV2(ctx);
      expect(result, isA<SystemPromptResult>());
      expect(result.systemPrompt, isNotEmpty);
      expect(result.estimatedTokens, greaterThan(0));
    });

    test('resolveL2Mode 返回 L2Mode', () {
      final ctx = SkillLoadContext(
        phase: TeachingPhase.p2PracticeLoop,
        attitude: AttitudeLevel.doubao,
        subphase: TeachingSubphase.diagnosis,
      );
      final mode = resolveL2Mode(ctx);
      expect(mode, isA<L2Mode>());
      expect(mode, L2Mode.diagnosis);
    });

    test('接口可被实现（implements 编译验证）', () {
      final impl = _TeachingContractAdapter();
      expect(impl, isA<TeachingCapability>());
    });
  });
}

class _TeachingContractAdapter implements TeachingCapability {
  @override
  SystemPromptResult buildSystemPrompt(SkillLoadContext ctx) =>
      buildSystemPromptV2(ctx);

  @override
  L2Mode resolveL2Mode(SkillLoadContext ctx) => resolveL2Mode(ctx);
}
