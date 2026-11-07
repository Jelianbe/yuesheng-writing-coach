// ─────────────────────────────────────────────────────────────
// 发现层出口类型（R-027 · T-20261106-04 接线批新增）。
//
// 逐字授权面 = `.ai/reports/2026-11-07-报批稿-发现层接线与S5落牙.md` §2.3。
// 字段集合本身是授权面的一部分：它决定 S-7（验证上下文不含发现层结论）
// 与 J2（帧隔离）能否成立 —— 加字段即改授权面。
//
// 零依赖：本文件不 import 任何项目内文件。`toHypotheses()` 放在
// `discovery_call.dart`（它需要 `VerificationHypothesis`，放这里会让
// 本文件反向依赖验证层）。
// ─────────────────────────────────────────────────────────────

/// 发现层出口枚举 —— 与 `kDiscoveryOutputFormat` 的 wire 值一一对应。
/// 新增值必须同时改本枚举与协议常量，并补一条负向用例，否则「恰三值」会退化。
enum DiscoveryExit { promoted, observation, unclassified }

/// 一条发现层观察。★ 与 `VerificationHypothesis` **刻意不同型**：
/// 本类型可携带 `inference` / `reason`（审计与展示用），验证层类型不带（S-7）。
/// 两者之间**只允许**经 `toHypotheses()` 单向映射，且映射丢弃 inference/reason。
class DiscoveryNote {
  final DiscoveryExit exit;
  final List<String> anchorQuotes; // 已通过 chunk.contains 子串校验
  final String inference; // 仅 promoted 非空
  final String reason; // 仅 observation / unclassified 非空
  final String syndromeId; // 可为空：出口一允许「暂无合适症候」

  const DiscoveryNote({
    required this.exit,
    required this.anchorQuotes,
    this.inference = '',
    this.reason = '',
    this.syndromeId = '',
  });
}

/// 解析结果 + **分母**。三数缺一，S-5 的牙就会退化成空集恒绿（章可循 §5-3）。
class DiscoveryParseResult {
  final int rawCount; // 模型实际给了几条（分母 ①）
  final int promoted; // 出口一且锚点通过（分母 ②）
  final int dropped; // 协议违规被作废的条数
  final List<DiscoveryNote> notes;

  const DiscoveryParseResult({
    required this.rawCount,
    required this.promoted,
    required this.dropped,
    required this.notes,
  });

  static const DiscoveryParseResult empty = DiscoveryParseResult(
    rawCount: 0,
    promoted: 0,
    dropped: 0,
    notes: [],
  );
}
