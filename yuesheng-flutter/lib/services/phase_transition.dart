// ─────────────────────────────────────────────────────────────
// 教学阶段迁移合法性校验 — 复刻 utils/phase-transition.ts
// 纯函数，无副作用
// 规则：P0→P1→P2→P3→P4 单向递进，P4→P2 允许回退
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';

const List<TeachingPhase> _kPhaseOrder = [
  TeachingPhase.p0Engage,
  TeachingPhase.p1World,
  TeachingPhase.p2PracticeLoop,
  TeachingPhase.p3Training,
  TeachingPhase.p4Review,
];

/// 获取下一个合法阶段（用于自动迁移）
///
/// P0→P1→P2→P3→P4 单向递进，P4 无下一阶段返回 null。
/// 注意：P4→P2 的回退由 [validatePhaseTransition] 处理，本函数不涉及。
TeachingPhase? nextPhase(TeachingPhase current) {
  final idx = _kPhaseOrder.indexOf(current);
  if (idx == -1 || idx >= _kPhaseOrder.length - 1) return null;
  return _kPhaseOrder[idx + 1];
}

/// 教学阶段迁移合法性校验（纯函数）
///
/// - 同阶段（P0→P0 等）：合法（无迁移）
/// - P0→P1、P1→P2、P2→P3、P3→P4：合法（正常递进）
/// - P4→P2：合法（下一个训练周期重新进入）
/// - 其他跳级或回退：不合法
bool validatePhaseTransition(TeachingPhase current, TeachingPhase suggested) {
  if (current == suggested) return true;
  final currentIdx = _kPhaseOrder.indexOf(current);
  final suggestedIdx = _kPhaseOrder.indexOf(suggested);
  if (currentIdx == -1 || suggestedIdx == -1) return false;
  // 正常递进：P0→P1→P2→P3→P4
  if (suggestedIdx == currentIdx + 1) return true;
  // 允许回退：P4→P2（下一训练周期重新进入）
  if (current == TeachingPhase.p4Review &&
      suggested == TeachingPhase.p2PracticeLoop) {
    return true;
  }
  return false;
}

/// 早期阶段（P0/P1）跨一格迁移的确定性降级目标（C-1，ADR-C54 §4-C-1）
///
/// C54 首诊场景：P0→P1 与 P1→P2 两个迁移信号同时成立，但 suggested_phase
/// 是单值——AI 无论填哪个都可能跨级（P0+P2）。本函数把「早期恰好跨一格」
/// 的非法建议降级为相邻递进目标，其余情况返回 null（维持原拦截）。
///
/// 边界（收窄条件，验证见 test/services/evaluation_service_test.dart）：
/// - P0→P2（C54 首诊）→ 降级 P1
/// - P1→P3 → 降级 P2
/// - P2→P4 → null（c>1，维持拦截——保住既有用例 #1 的拦截语义）
/// - P0→P3 / P0→P4 → null（跨超过一格）
/// - 任何回退 → null
/// - P0→P1（合法相邻）→ null（走 validatePhaseTransition 原合法路径）
TeachingPhase? clampEarlyPhaseSkip(
  TeachingPhase current,
  TeachingPhase suggested,
) {
  final c = _kPhaseOrder.indexOf(current);
  final s = _kPhaseOrder.indexOf(suggested);
  if (c < 0 || s < 0) return null;
  if (c > 1) return null; // 仅 P0(0) / P1(1)
  if (s != c + 2) return null; // 仅恰好跨一格
  return _kPhaseOrder[c + 1]; // 降级为相邻递进
}
