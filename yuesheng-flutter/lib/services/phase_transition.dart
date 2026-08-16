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
