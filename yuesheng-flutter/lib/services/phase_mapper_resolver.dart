// ─────────────────────────────────────────────────────────────
// phase-mapper 决策矩阵代码侧落地 — 复刻 services/phase-mapper-resolver.ts
// 真源：src/assets/skills/phase-mapper.ts L40-62（4 条决策规则）
//
// 职责：在 chat-service 调用 updatePhase / updateBeginnerLevel 落库前，
// 对 AI 输出的迁移信号进行互斥校验，防止冲突信号被同时写入。
//
// 4 条规则：
// - 规则1（N0-N2 P 系虚拟挂起）：effectivePhase=null，忽略 suggested_phase
// - 规则2（N3-N4 切换到 P 系）：effectivePhase=suggestedPhase
// - 规则3（系统 phase 降级特例）：N3+P1→P2；N2+P3→拒绝 P3，锁 N2
// - 规则4（默认回退）：无迁移信号时不更新
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';

/// resolver 输入
class PhaseMapperInput {
  final TeachingPhase? currentPhase;
  final BeginnerLevel? currentBeginnerLevel;
  final TeachingPhase? suggestedPhase;
  final BeginnerLevel? suggestedBeginnerLevel;
  final int consecutiveFailedTrainings;

  const PhaseMapperInput({
    required this.currentPhase,
    required this.currentBeginnerLevel,
    this.suggestedPhase,
    this.suggestedBeginnerLevel,
    this.consecutiveFailedTrainings = 0,
  });
}

/// 被忽略的 AI 输出字段
enum IgnoredField {
  suggestedPhase('suggested_phase'),
  suggestedBeginnerLevel('suggested_beginner_level');

  final String value;
  const IgnoredField(this.value);
}

/// resolver 输出
class PhaseMapperOutput {
  final TeachingPhase? effectivePhase;
  final BeginnerLevel? effectiveBeginnerLevel;
  final List<IgnoredField> ignoredFields;
  final String reason;
  final int appliedRule; // 1 | 2 | 3 | 4

  const PhaseMapperOutput({
    required this.effectivePhase,
    required this.effectiveBeginnerLevel,
    required this.ignoredFields,
    required this.reason,
    required this.appliedRule,
  });
}

/// N 系单向递进顺序（N0→N1→N2→N3→N4）
const List<BeginnerLevel> _kBeginnerOrder = [
  BeginnerLevel.n0Engage,
  BeginnerLevel.n1Elements,
  BeginnerLevel.n2Scene,
  BeginnerLevel.n3Diagnose,
  BeginnerLevel.n4Independent,
];

/// 校验 N 系单向递进
/// - 同级合法
/// - 前进 1 步合法
/// - 跳跃非法
/// - 降级非法
bool _isValidProgression(BeginnerLevel from, BeginnerLevel to) {
  final fromIdx = _kBeginnerOrder.indexOf(from);
  final toIdx = _kBeginnerOrder.indexOf(to);
  return toIdx == fromIdx || toIdx == fromIdx + 1;
}

/// 按 phase-mapper.ts skill 的 4 条决策规则，对 AI 输出的迁移信号进行代码侧校验
PhaseMapperOutput resolvePhaseMapper(PhaseMapperInput input) {
  final currentBeginnerLevel = input.currentBeginnerLevel;
  final suggestedPhase = input.suggestedPhase;
  final suggestedBeginnerLevel = input.suggestedBeginnerLevel;
  final consecutiveFailedTrainings = input.consecutiveFailedTrainings;

  final ignoredFields = <IgnoredField>[];

  // ============ Step 1: 确定生效的 beginner_level ============

  BeginnerLevel? resolverBeginnerLevel;
  BeginnerLevel? outputBeginnerLevel;

  if (suggestedBeginnerLevel != null) {
    if (currentBeginnerLevel == null) {
      // B6: 首次激活，接受任意 suggested
      resolverBeginnerLevel = suggestedBeginnerLevel;
      outputBeginnerLevel = suggestedBeginnerLevel;
    } else {
      final valid = _isValidProgression(
        currentBeginnerLevel,
        suggestedBeginnerLevel,
      );
      if (valid) {
        resolverBeginnerLevel = suggestedBeginnerLevel;
        outputBeginnerLevel = suggestedBeginnerLevel;
      } else {
        // 跳跃或降级：拒绝，保持 current
        resolverBeginnerLevel = currentBeginnerLevel;
        outputBeginnerLevel = currentBeginnerLevel;
        ignoredFields.add(IgnoredField.suggestedBeginnerLevel);
      }
    }
  } else {
    // 未提供 suggested
    resolverBeginnerLevel = currentBeginnerLevel;
    outputBeginnerLevel = null;
  }

  // decisionBeginnerLevel: 用于规则1/2 分支选择（应用规则4 默认 N3）
  final decisionBeginnerLevel =
      resolverBeginnerLevel ?? BeginnerLevel.n3Diagnose;

  // B3c-2: N3 降级触发检查
  const n3DowngradeThreshold = 3;
  if (currentBeginnerLevel == BeginnerLevel.n3Diagnose &&
      consecutiveFailedTrainings >= n3DowngradeThreshold &&
      suggestedBeginnerLevel == null) {
    return PhaseMapperOutput(
      effectivePhase: null,
      effectiveBeginnerLevel: BeginnerLevel.n2Scene,
      ignoredFields: const [],
      reason: 'B3c-2：N3 连续 $consecutiveFailedTrainings 次训练失败，自动降级到 N2',
      appliedRule: 4,
    );
  }

  // ============ Step 2: 决定 phase ============

  // 规则4: 无任何迁移信号
  if (suggestedPhase == null && suggestedBeginnerLevel == null) {
    return const PhaseMapperOutput(
      effectivePhase: null,
      effectiveBeginnerLevel: null,
      ignoredFields: [],
      reason: '无迁移信号',
      appliedRule: 4,
    );
  }

  // 规则3 特例（N3+P1→P2 提升）
  // C-3 收窄（ADR-C54 §4-C-3）：current 尚未越过 P1（null 或 P0）时不提升。
  // 此时 P0→P1 是合法相邻递进，提升会把一个合法信号改写成非法的 P0→P2
  // 被 validatePhaseTransition 拦截——与规则 3 的设计意图（「P1 世界观对
  // N3 学员太浅」）相反：P0 学员还没到 P1，不存在「太浅」的问题。
  // 收窄后该场景走规则 2 原样透传 P1。
  final notPastP1 =
      input.currentPhase == null ||
      input.currentPhase == TeachingPhase.p0Engage;
  if (resolverBeginnerLevel == BeginnerLevel.n3Diagnose &&
      suggestedPhase == TeachingPhase.p1World &&
      !notPastP1) {
    return PhaseMapperOutput(
      effectivePhase: TeachingPhase.p2PracticeLoop,
      effectiveBeginnerLevel: outputBeginnerLevel,
      ignoredFields: ignoredFields,
      reason: '规则3：N3+P1 降级到 P2（P1 世界观对 N3 学员太浅）',
      appliedRule: 3,
    );
  }
  if (resolverBeginnerLevel == BeginnerLevel.n2Scene &&
      suggestedPhase == TeachingPhase.p3Training) {
    return PhaseMapperOutput(
      effectivePhase: null,
      effectiveBeginnerLevel: BeginnerLevel.n2Scene,
      ignoredFields: [IgnoredField.suggestedPhase, ...ignoredFields],
      reason: '规则3：N2+P3 拒绝 P3 落库（N2 学员还不会自己练）',
      appliedRule: 3,
    );
  }

  // 规则1: N0/N1/N2 P 系虚拟挂起
  if (decisionBeginnerLevel == BeginnerLevel.n0Engage ||
      decisionBeginnerLevel == BeginnerLevel.n1Elements ||
      decisionBeginnerLevel == BeginnerLevel.n2Scene) {
    if (suggestedPhase != null) {
      ignoredFields.add(IgnoredField.suggestedPhase);
    }
    return PhaseMapperOutput(
      effectivePhase: null,
      effectiveBeginnerLevel: outputBeginnerLevel,
      ignoredFields: ignoredFields,
      reason: '规则1：${decisionBeginnerLevel.value} 阶段 P 系虚拟挂起',
      appliedRule: 1,
    );
  }

  // 规则2: N3/N4 切换到 P 系
  if (suggestedPhase != null) {
    return PhaseMapperOutput(
      effectivePhase: suggestedPhase,
      effectiveBeginnerLevel: outputBeginnerLevel,
      ignoredFields: ignoredFields,
      reason:
          '规则2：${decisionBeginnerLevel.value} 接受 suggested_phase=${suggestedPhase.value}',
      appliedRule: 2,
    );
  }
  return PhaseMapperOutput(
    effectivePhase: null,
    effectiveBeginnerLevel: outputBeginnerLevel,
    ignoredFields: ignoredFields,
    reason: '规则2：${decisionBeginnerLevel.value} 维持当前 phase',
    appliedRule: 2,
  );
}
