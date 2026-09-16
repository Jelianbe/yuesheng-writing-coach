// ─────────────────────────────────────────────────────────────
// P2-9：FSRS 间隔重复调度（确定性纯函数，无参数拟合）
//
// 设计裁定（ADR 2026-09-16-p2-structural §P2-9）：
//   - 不做完整 FSRS-6 参数拟合（项目无大批量回忆数据），采用其核心形状：
//     稳定度随连续通过指数增长、失败重置、间隔封顶。
//   - 间隔序列 1/2/4/8/14（封顶 14 天）与 training_evaluator 的
//     fsrsReady 判据（fsrsIntervalDays >= 14 && consolidationObservations >= 3）
//     对齐：连续通过 ≥5 次 + 巩固观察 ≥3 次才走 FSRS 毕业路径。
//   - 可提取性（retrievability）为简化线性衰减，仅用于 prompt 注入
//     「到期/临期/新鲜」分级，不进状态机判据。
// ─────────────────────────────────────────────────────────────

/// 连续通过次数 → 下次复习间隔（天）。指数增长，封顶 14。
///
/// - n=0（最近一次未通过 / 无记录）→ 1 天（尽快重测）
/// - n=1..4 → 2^(n-1) 天
/// - n>=5 → 14 天（封顶；达到 training_evaluator 的 FSRS 毕业阈值）
int fsrsIntervalDaysFor(int consecutivePasses) {
  if (consecutivePasses <= 0) return 1;
  if (consecutivePasses >= 5) return 14;
  return 1 << (consecutivePasses - 1); // 2^(n-1)
}

/// 是否到期需复习：距上次训练 ≥ 计算间隔。
bool isReviewDue(int consecutivePasses, int daysSinceLastObservation) {
  if (daysSinceLastObservation < 0) return false;
  return daysSinceLastObservation >= fsrsIntervalDaysFor(consecutivePasses);
}

/// 可提取性（0.0~1.0）：简化线性衰减。
///
/// 1.0 = 刚训练完；随天数线性衰减到 0（达间隔后）；无训练记录返回 1.0
/// （无记录不复习——避免把「从未训练」误判为「最该复习」）。
double retrievabilityFor(int consecutivePasses, int daysSinceLastObservation) {
  if (daysSinceLastObservation < 0) return 1.0;
  final interval = fsrsIntervalDaysFor(consecutivePasses);
  if (interval <= 0) return 1.0;
  final r = 1.0 - daysSinceLastObservation / interval;
  return r.clamp(0.0, 1.0);
}

/// 复习状态分级（供 prompt 注入段使用）。
enum ReviewStatus { fresh, upcoming, due }

/// 判定复习状态：
/// - due：已到期（≥间隔）——本轮应优先处理
/// - upcoming：未到期但可提取性 ≤0.5（过半衰减）——可提前预防性巩固
/// - fresh：刚练过（可提取性 >0.5）——无需处理
ReviewStatus reviewStatusFor(
  int consecutivePasses,
  int daysSinceLastObservation,
) {
  if (isReviewDue(consecutivePasses, daysSinceLastObservation)) {
    return ReviewStatus.due;
  }
  if (retrievabilityFor(consecutivePasses, daysSinceLastObservation) <= 0.5) {
    return ReviewStatus.upcoming;
  }
  return ReviewStatus.fresh;
}
