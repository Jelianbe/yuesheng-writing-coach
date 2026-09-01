// ─────────────────────────────────────────────────────────────
// resolvePhaseMapper 单元测试（ADR-C54 §7.2，填补 N7 空缺）
//
// 该纯函数承载 4 条决策规则 + N 系递进校验，且规则 3 会改写 AI 意图，
// 此前零单测守护（ADR-C54 §2.7 / §8-N7）。覆盖：
//   规则1: N0/N1/N2 P 系虚拟挂起（suggested_phase 整个丢弃）
//   规则3 + C-3 收窄: current 未越过 P1 时 N3+P1 原样透传（验收点）
//   规则3 既有行为: current 已到 P1+ 时 N3+P1 仍提升 P2
//   规则3: N2+P3 拒绝落库
//   规则2: N3/N4 透传
//   默认回退: beginnerLevel null → decisionBeginnerLevel = N3
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/phase_mapper_resolver.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('规则1：N0/N1/N2 P 系虚拟挂起', () {
    test('N0 + suggested_phase → effectivePhase null 且 suggestedPhase 被忽略', () {
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: TeachingPhase.p0Engage,
          currentBeginnerLevel: BeginnerLevel.n0Engage,
          suggestedPhase: TeachingPhase.p1World,
        ),
      );
      expect(out.effectivePhase, isNull);
      expect(out.ignoredFields, contains(IgnoredField.suggestedPhase));
      expect(out.appliedRule, 1);
    });

    test('N2 + suggested_phase → 同样挂起', () {
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: TeachingPhase.p2PracticeLoop,
          currentBeginnerLevel: BeginnerLevel.n2Scene,
          suggestedPhase: TeachingPhase.p3Training,
        ),
      );
      expect(out.effectivePhase, isNull);
      expect(out.ignoredFields, contains(IgnoredField.suggestedPhase));
    });
  });

  group('规则3 特例', () {
    test('C-3 收窄：current=P0 + N3 + P1 → 原样透传 P1（不提升 P2）', () {
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: TeachingPhase.p0Engage,
          currentBeginnerLevel: BeginnerLevel.n3Diagnose,
          suggestedPhase: TeachingPhase.p1World,
        ),
      );
      expect(
        out.effectivePhase,
        TeachingPhase.p1World,
        reason:
            'C-3 验收点：P0 学员还没到 P1，P0→P1 是合法信号，'
            '提升为 P2 会变成非法的 P0→P2 被拦截',
      );
      expect(out.appliedRule, 2);
    });

    test('C-3 收窄：current=null（状态未知）+ N3 + P1 → 同样透传 P1', () {
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: null,
          currentBeginnerLevel: BeginnerLevel.n3Diagnose,
          suggestedPhase: TeachingPhase.p1World,
        ),
      );
      expect(out.effectivePhase, TeachingPhase.p1World);
    });

    test('既有行为不变：current=P1 + N3 + P1 → 仍提升为 P2', () {
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: TeachingPhase.p1World,
          currentBeginnerLevel: BeginnerLevel.n3Diagnose,
          suggestedPhase: TeachingPhase.p1World,
        ),
      );
      expect(
        out.effectivePhase,
        TeachingPhase.p2PracticeLoop,
        reason: 'current 已到 P1，N3+P1 提升语义维持',
      );
      expect(out.appliedRule, 3);
    });

    test('既有行为不变：current=P2 + N3 + P1 → 仍提升为 P2', () {
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: TeachingPhase.p2PracticeLoop,
          currentBeginnerLevel: BeginnerLevel.n3Diagnose,
          suggestedPhase: TeachingPhase.p1World,
        ),
      );
      expect(out.effectivePhase, TeachingPhase.p2PracticeLoop);
      expect(out.appliedRule, 3);
    });

    test('N2 + P3 → 拒绝 P3 落库，锁 N2', () {
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: TeachingPhase.p2PracticeLoop,
          currentBeginnerLevel: BeginnerLevel.n2Scene,
          suggestedPhase: TeachingPhase.p3Training,
        ),
      );
      expect(out.effectivePhase, isNull);
      expect(out.effectiveBeginnerLevel, BeginnerLevel.n2Scene);
      expect(out.ignoredFields, contains(IgnoredField.suggestedPhase));
      expect(out.appliedRule, 3);
    });
  });

  group('规则2：N3/N4 透传', () {
    test('N3 + P2 → 透传 P2', () {
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: TeachingPhase.p0Engage,
          currentBeginnerLevel: BeginnerLevel.n3Diagnose,
          suggestedPhase: TeachingPhase.p2PracticeLoop,
        ),
      );
      expect(out.effectivePhase, TeachingPhase.p2PracticeLoop);
      expect(out.appliedRule, 2);
    });

    test('N4 + P3 → 透传 P3', () {
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: TeachingPhase.p2PracticeLoop,
          currentBeginnerLevel: BeginnerLevel.n4Independent,
          suggestedPhase: TeachingPhase.p3Training,
        ),
      );
      expect(out.effectivePhase, TeachingPhase.p3Training);
      expect(out.appliedRule, 2);
    });
  });

  group('规则4 与默认回退', () {
    test('无任何迁移信号 → 规则4', () {
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: TeachingPhase.p2PracticeLoop,
          currentBeginnerLevel: BeginnerLevel.n3Diagnose,
        ),
      );
      expect(out.effectivePhase, isNull);
      expect(out.effectiveBeginnerLevel, isNull);
      expect(out.appliedRule, 4);
    });

    test('beginnerLevel=null（默认回退 N3）+ P1（current=P0）→ 透传 P1', () {
      // ADR §2.4：beginner_level 为 null 时 decisionBeginnerLevel 默认 N3，
      // 与 prompt 侧「N 系进度未知默认为 N3」一致（skills_l1_core_p1.dart:61）
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: TeachingPhase.p0Engage,
          currentBeginnerLevel: null,
          suggestedPhase: TeachingPhase.p1World,
        ),
      );
      expect(
        out.effectivePhase,
        TeachingPhase.p1World,
        reason: '默认 N3 + current=P0 走 C-3 收窄后的透传路径',
      );
    });

    test('beginnerLevel=null（默认 N3）+ 无 suggested → 维持 phase', () {
      final out = resolvePhaseMapper(
        PhaseMapperInput(
          currentPhase: TeachingPhase.p2PracticeLoop,
          currentBeginnerLevel: null,
          suggestedBeginnerLevel: BeginnerLevel.n3Diagnose,
        ),
      );
      // 只给 beginner 信号，phase 维持
      expect(out.effectivePhase, isNull);
      expect(out.effectiveBeginnerLevel, BeginnerLevel.n3Diagnose);
    });
  });
}
