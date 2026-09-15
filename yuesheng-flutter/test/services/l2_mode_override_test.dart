// U2 批（2026-09-15）：契约 `modeOverride` 不变量测试。
//
// 目的：证明「一处决议、向下传递」成立 —— 覆盖时
// `SystemPromptResult.l2Mode` 与**实际装配的 skill 组**必然一致，
// 且与「天然就该用该组的上下文」逐字节等价。
//
// 归因：docs/audits/U1批-共享前置落地与缓存偏移实证-2026-09-15.md §5.2

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/teaching_capability.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/l2_route_hysteresis.dart';
import 'package:writingcoach/services/skill_layers.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 最长公共前缀长度（用于验证 L1 段未被覆盖影响）。
int _commonPrefixLen(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return i;
  }
  return n;
}

void main() {
  const impl = TeachingCapabilityImpl();

  /// P2 诊断子阶段 ⇒ 天然决议 diagnosis。
  const diagCtx = SkillLoadContext(
    phase: TeachingPhase.p2PracticeLoop,
    attitude: AttitudeLevel.doubao,
    subphase: TeachingSubphase.diagnosis,
  );

  /// P2 练习子阶段 ⇒ 天然决议 training。
  const trainCtx = SkillLoadContext(
    phase: TeachingPhase.p2PracticeLoop,
    attitude: AttitudeLevel.doubao,
    subphase: TeachingSubphase.practice,
  );

  group('契约 modeOverride · 默认路径零影响', () {
    test('不传 override ⇒ 决议为上下文自然结果', () {
      expect(impl.buildSystemPrompt(diagCtx).l2Mode, L2Mode.diagnosis);
      expect(impl.buildSystemPrompt(trainCtx).l2Mode, L2Mode.training);
    });

    test('显式传 null 与不传等价（签名向后兼容）', () {
      expect(
        impl.buildSystemPrompt(diagCtx, modeOverride: null).systemPrompt,
        impl.buildSystemPrompt(diagCtx).systemPrompt,
      );
    });

    test('顶层纯函数与契约实现同源（默认路径）', () {
      expect(
        buildSystemPromptV2(diagCtx).systemPrompt,
        impl.buildSystemPrompt(diagCtx).systemPrompt,
      );
    });
  });

  group('契约 modeOverride · 覆盖生效与装配一致', () {
    test('诊断上下文 + override=training ⇒ l2Mode 反映覆盖值', () {
      final natural = impl.buildSystemPrompt(diagCtx);
      final forced = impl.buildSystemPrompt(
        diagCtx,
        modeOverride: L2Mode.training,
      );
      expect(natural.l2Mode, L2Mode.diagnosis);
      expect(forced.l2Mode, L2Mode.training);
    });

    test('★ 装配一致：override 结果与天然训练上下文逐字节相同', () {
      final forced = impl.buildSystemPrompt(
        diagCtx,
        modeOverride: L2Mode.training,
      );
      final natural = impl.buildSystemPrompt(trainCtx);
      expect(forced.l2Mode, natural.l2Mode);
      expect(forced.systemPrompt, natural.systemPrompt);
      expect(forced.loadedSkillIds, natural.loadedSkillIds);
      expect(forced.estimatedTokens, natural.estimatedTokens);
    });

    test('★ 反向：训练上下文 + override=diagnosis 等价于天然诊断上下文', () {
      final forced = impl.buildSystemPrompt(
        trainCtx,
        modeOverride: L2Mode.diagnosis,
      );
      final natural = impl.buildSystemPrompt(diagCtx);
      expect(forced.l2Mode, L2Mode.diagnosis);
      expect(forced.systemPrompt, natural.systemPrompt);
    });

    test('★ 被覆盖掉的组的独有 skill 不残留（防静默不一致）', () {
      final trainIds = getL2SkillIds(
        L2Mode.training,
      ).map((r) => r.skillId).toSet();
      final diagOnly = getL2SkillIds(
        L2Mode.diagnosis,
      ).map((r) => r.skillId).toSet().difference(trainIds);

      expect(diagOnly, isNotEmpty, reason: '两组应有独占项，否则本测无意义');

      final forced = impl.buildSystemPrompt(
        diagCtx,
        modeOverride: L2Mode.training,
      );
      for (final id in diagOnly) {
        expect(forced.loadedSkillIds, isNot(contains(id)), reason: id);
      }
    });
  });

  group('契约 modeOverride · 只影响 L2 段', () {
    test('L1 段（含态度档 / 位置判断 / 边界声明）不受 override 影响', () {
      final natural = impl.buildSystemPrompt(diagCtx);
      final forced = impl.buildSystemPrompt(
        diagCtx,
        modeOverride: L2Mode.training,
      );

      // 诊断组首个 L2 skill 的注入位点 = L1 段长度（L1 在 L2 之前）。
      final firstL2Id = getL2SkillIds(L2Mode.diagnosis).first.skillId;
      final firstL2 = getSkill(firstL2Id);
      expect(firstL2, isNotNull, reason: '首个诊断组 skill 应已注册');

      final l1Len = natural.systemPrompt.indexOf(firstL2!.content);
      expect(l1Len, greaterThan(0), reason: 'L2 不应出现在开头');
      expect(
        _commonPrefixLen(natural.systemPrompt, forced.systemPrompt),
        greaterThanOrEqualTo(l1Len),
        reason: '前 $l1Len 字符（= L1 段）必须完全一致',
      );
    });
  });

  group('契约 modeOverride · 与迟滞器联动的调用协议', () {
    test('模拟 ChatService 决议序列（ctx → raw → 迟滞 → override）', () {
      final h = L2RouteHysteresis();
      final applied = <L2Mode>[];
      // 逐轮上下文与真实链路同形：raw 由 resolveL2Mode(ctx) 得出。
      for (final ctx in <SkillLoadContext>[
        diagCtx, // r1 诊断
        trainCtx, // r2 交作业（subphase=practice）
        diagCtx, // r3 练习后自动回切 ⇒ 应被抑制
        diagCtx, // r4 放行
      ]) {
        final raw = impl.resolveL2Mode(ctx);
        final ov = h.overrideFor('s1', raw);
        applied.add(impl.buildSystemPrompt(ctx, modeOverride: ov).l2Mode);
      }
      expect(applied, <L2Mode>[
        L2Mode.diagnosis,
        L2Mode.training,
        L2Mode.training, // ★ 抑制生效：仍装配训练组
        L2Mode.diagnosis,
      ]);
    });

    test('★ 抑制轮的实际装配 = 训练组（不只是 l2Mode 字段）', () {
      final h = L2RouteHysteresis();
      h.overrideFor('s1', impl.resolveL2Mode(diagCtx)); // r1
      h.overrideFor('s1', impl.resolveL2Mode(trainCtx)); // r2
      final ov = h.overrideFor('s1', impl.resolveL2Mode(diagCtx)); // r3 抑制
      expect(ov, L2Mode.training);

      final suppressed = impl.buildSystemPrompt(diagCtx, modeOverride: ov);
      final naturalTraining = impl.buildSystemPrompt(trainCtx);
      expect(suppressed.systemPrompt, naturalTraining.systemPrompt);
    });
  });
}
