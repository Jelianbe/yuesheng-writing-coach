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
///
/// ★ 本函数**签名刻意保持单参数不变**（批1·N2 决定）：用户自评的折算由调用方
/// 经 [effectivePassesFor] 完成，再把**同一个有效次数**喂给本函数与
/// [reviewStatusFor] —— 若改为「本函数内部折算」，则 `reviewStatusFor`
/// 仍用原始次数，会造成**「间隔」与「到期状态」口径不一致**（同一症候
/// 报「间隔 8 天」却同时判「已到期」）。折算在调用方做一次，两处必然一致。
int fsrsIntervalDaysFor(int consecutivePasses) {
  if (consecutivePasses <= 0) return 1;
  if (consecutivePasses >= 5) return 14;
  return 1 << (consecutivePasses - 1); // 2^(n-1)
}

/// FSRS 回忆难度自评档位（批1·N2，Anki 四档）。
///
/// ★ 与「掌握证据」三维自评（`TrainingSelfAssessment.confidenceRating` /
/// explanationText / transferText，v32）**语义不同**，勿混用：
/// 三维 = 「对这次改动的把握」（喂 `mastery_evidence` 门控）；
/// 本档 = 「这次回忆/作答有多难」（喂间隔调度）。
enum FsrsRating {
  again('again'),
  hard('hard'),
  good('good'),
  easy('easy');

  const FsrsRating(this.value);

  /// 落库值（`training_results.user_rating`）。
  final String value;

  /// 解析落库值。未知 / `null` ⇒ `null`（**不抛异常**）。
  ///
  /// 该列是 TEXT 裸列（无 CHECK 约束）：旧数据、人工写入、跨版本都可能出现
  /// 无法识别的值。解析失败**降级为「无自评」**（退回既有行为）而非报错——
  /// 与 R-028「降级不阻断」一致。
  static FsrsRating? fromValue(String? raw) {
    if (raw == null) return null;
    for (final r in FsrsRating.values) {
      if (r.value == raw) return r;
    }
    return null;
  }
}

/// 自评档位 → 「有效连续通过次数」（批1·N2）。
///
/// - `again` **归零**（不是减一）：语义是「这次没能想起来」⇒ 稳定度重置
/// - `hard` −1（保守一档）/ `good` 0（不变）/ `easy` +1（加速一档）
///
/// 结果非负（下界 0）。**只在有自评时调用**；无自评的路径不经过本函数，
/// 以保证 `fsrsIntervalDaysFor` 的缺省行为与改造前一致。
int effectivePassesFor(int consecutivePasses, FsrsRating rating) {
  final adjusted = switch (rating) {
    FsrsRating.again => 0,
    FsrsRating.hard => consecutivePasses - 1,
    FsrsRating.good => consecutivePasses,
    FsrsRating.easy => consecutivePasses + 1,
  };
  return adjusted < 0 ? 0 : adjusted;
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
