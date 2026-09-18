// ─────────────────────────────────────────────────────────────
// llm_cost — LLM 成本折算的**唯一实现点**（`N7` 批次）
//
// 为什么需要本文件：用量埋点（`llm_call_log_sink.dart`）**刻意只存原始
// token、不存成本** —— 理由写在它自己的文件头：「单价会变，且成本结论须
// 显式声明峰/闲时段 ⇒ 折算留给查询侧」。因此**折算侧此前只存在于 Python
// 审计脚本与台账文字里，`lib/` 下一个实现都没有**。本文件把那个口径
// **搬进产品代码**，供 UI（设置页「本周用量」）复用。
//
// ## 单价口径（**不得在本文件之外另立一套**）
//
// | 项 | 闲时（元 / 百万 token） |
// |---|---|
// | 命中缓存的输入（hit） | 0.02 |
// | 未命中缓存的输入（miss） | 1.00 |
// | 输出（含推理） | 4.00 |
//
// **峰时 = 闲时 × 2**（`kPeakMultiplier`）。
//
// ## 峰 / 闲时段定义
//
// ★ **高峰时段 = 北京时间 周一至周五 09:00–12:00、14:00–18:00；其余空闲**
//   —— 出处 `.ai/LEDGER-DETAIL.md:806`（原文即此，含「×0.5」的等价表述）。
//
// ## 口径的实测背书（不是照抄单价表）
//
// `.ai/LEDGER-DETAIL.md:1572`：结算后**实花 ¥0.1500** vs 脚本按
// **闲时 0.02 / 1.00 / 4.00** 折算 **¥0.15135** ⇒ **1.009×**（折算准确）。
// ⇒ 该三档单价**已被真实账单回填验证**，故本文件直接采用，不再另采样本。
//
// ## ⚠️ 两条最容易错的点（本文件刻意防住）
//
// 1. **时区**：峰闲窗是**北京时间**定义的，**不是设备本地时**。设备若不在
//    UTC+8（模拟器 / 海外用户 / 用户改了系统时区），用 `DateTime.now().hour`
//    判档会**整体错档**（成本差 2 倍）。故本文件**一律显式 `toUtc() + 8h`**，
//    调用方只传 UTC 时刻、**不传本地时刻**。
// 2. **别把 reasoning 再加一遍**：`completion_tokens` 在协议层**已含**推理
//    token（`LlmUsageTotals.completionTokens` 注释、`llm_usage.dart` 同），
//    `reasoning_tokens` 是**拆解视图**而非额外计费项 ⇒ 输出档只乘
//    `completionTokens`，**不得**再加 `reasoningTokens`。
// ─────────────────────────────────────────────────────────────

/// 三档单价（元 / **百万** token）。不可变。
class LlmPrice {
  /// 命中缓存的输入 token 单价
  final double cachedPerM;

  /// 未命中缓存的输入 token 单价
  final double missPerM;

  /// 输出 token 单价（**已含推理**，别再单独加 `reasoning_tokens`）
  final double outputPerM;

  const LlmPrice({
    required this.cachedPerM,
    required this.missPerM,
    required this.outputPerM,
  });

  @override
  String toString() =>
      'LlmPrice(hit=$cachedPerM, miss=$missPerM, out=$outputPerM / 百万)';
}

/// 闲时单价（= 基准档）。出处见文件头。
const LlmPrice kLlmOffPeakPrice = LlmPrice(
  cachedPerM: 0.02,
  missPerM: 1.00,
  outputPerM: 4.00,
);

/// 峰时倍数（峰时单价 = 闲时 × 本值）。
const double kPeakMultiplier = 2.0;

/// 北京时区相对 UTC 的固定偏移。
///
/// 中国全境单一时区、**无夏令时** ⇒ 用固定偏移即可，无需时区库。
const Duration kCstOffset = Duration(hours: 8);

/// 高峰时段的整点区间（**北京时间**，左闭右开）。
const List<({int from, int to})> kPeakHourRangesCst = [
  (from: 9, to: 12),
  (from: 14, to: 18),
];

/// 北京时间墙钟视图。
///
/// 返回的 `DateTime` 其 **UTC 标记位被复用为「北京时间字段」**（不吃设备时区）。
/// 私有：只供本文件的判档 / 求周起点使用，不外泄以免被误当真实 UTC。
DateTime _cstWallClock(DateTime atUtc) => atUtc.toUtc().add(kCstOffset);

/// 该时刻是否落在**高峰时段**（北京时间 周一至周五 09:00–12:00 / 14:00–18:00）。
///
/// ★ 入参必须是 **UTC 时刻**（`DateTime` 若带本地时区会自动 `toUtc()`，
///   但要显式传 UTC 才不会被误读；本函数**不读设备时区**）。
bool isPeakHourCst(DateTime atUtc) {
  final cst = _cstWallClock(atUtc);
  // DateTime.weekday: 1=周一 … 7=周日 ⇒ 仅周一至周五计高峰。
  if (cst.weekday > DateTime.friday) return false;
  for (final r in kPeakHourRangesCst) {
    if (cst.hour >= r.from && cst.hour < r.to) return true;
  }
  return false;
}

/// 单次 / 累计 cost（元）。**逐笔按该笔的发生时刻判峰闲**后再求和 ——
/// 一批调用跨了峰闲边界时，不能整批乘同一个倍数。
///
/// [missTokens] 用埋点里现成的 `miss_tokens` 字段（勿自行用
/// `prompt - cached` 重算：两处算会分叉，同 `DECISIONS §4-41` 的教训）。
double llmCostCny({
  required int cachedTokens,
  required int missTokens,
  required int completionTokens,
  required DateTime atUtc,
  LlmPrice price = kLlmOffPeakPrice,
}) {
  final mult = isPeakHourCst(atUtc) ? kPeakMultiplier : 1.0;
  final weighted =
      cachedTokens * price.cachedPerM +
      missTokens * price.missPerM +
      completionTokens * price.outputPerM;
  return weighted * mult / 1000000.0;
}

/// 「本周」起点 = 北京时间**本周一 00:00**，返回其 **UTC epoch 秒**
/// （与 `error_logs.created_at` 同一标度，可直接进 SQL 比较）。
///
/// 一周的第一天取**周一**（与北京时间惯例一致；`DateTime.monday == 1`）。
int weekStartEpochSecCst(DateTime nowUtc) {
  final cst = _cstWallClock(nowUtc);
  // 以 UTC 字段承载「北京时间的年月日」
  final dayStartCst = DateTime.utc(cst.year, cst.month, cst.day);
  final mondayCst = dayStartCst.subtract(Duration(days: cst.weekday - 1));
  // 把墙钟换回真实 UTC：减去偏移
  return mondayCst.subtract(kCstOffset).millisecondsSinceEpoch ~/ 1000;
}
