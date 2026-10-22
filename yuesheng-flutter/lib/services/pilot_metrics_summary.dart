// ─────────────────────────────────────────────────────────────
// pilot_metrics_summary — 「引文锚定」卡聚合读数装配（纯函数）
// （T-20261018-06 · D 议题 · 设计批 2026-10-22 舰长「批 · 删 · 引文锚定」）
//
// 上游裁定链：DECISIONS §4-232（R-029「都批」）——
//   只呈聚合计数 · 不含症候维度 · 本地零外发 · 停写类不呈 ·
//   anchor_probe 可呈（只呈 AER 聚合；明细含引文原文片段永不进 UI 树）。
// 文案：设计批 R-027 五条（舰长 2026-10-22「批」）+ 待裁 A「删」（启动次数行不实施）。
//
// 职责：把 pilot_metric_events 表里 anchor_probe 类型的 payload 明细
// （AnchorProbeReport.toPayload() 的 JSON，落库纪律：只存明细不存比率）
// 现算成卡级聚合读数——AER = (anchored 条数 / 全部引文条数)。
//
// 隐私边界（守卫 P1/P2 机器判据，见 scripts/check_pilot_surface.py）：
//   本函数**不输出** payload 明细里的任何原文字段——引文原文片段
//   （toPayload 的 'h' 键）与症候 ID（'s' 键）在解析层即被丢弃，
//   只累计状态码 ⇒ UI 树结构上不可能出现原文（非「不渲染」，是「拿不到」）。
//
// payload 键协议与 p0_verify/anchor_probe.dart toPayload() 耦合：
//   'v' 版本（≠ 传入版本 fail-closed 跳过，不猜未来结构）·
//   'items[].k' 状态码（AnchorStatus.code 同口径：anchored =
//   {ok_exact, ok_ws, ok_width, ok_joined, ambiguous}）·
//   'items[].h'/'items[].s' —— **本函数故意不读**（隐私边界，见上）。
//
// 纯函数纪律：不 import Repository / DB / Provider / p0_verify；
// 输入 = 已按类型过滤的 payload 字符串列表 + payload 版本号（调用方传
// kAnchorPayloadVersion）⇒ 可单测、零 drift 依赖。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

/// anchor_probe payload 的「锚定成功」状态码集合（分子）。
///
/// 与 `AnchorStatus.isAnchored`（anchor.dart:47）**同口径**：三级精确命中
/// + 拼合命中 + ambiguous 均计入分子；分母 = 全部 items 条数
/// （空白 evidence 本就不进 items，天然不在分母里）。
const Set<String> kAnchoredStatusCodes = <String>{
  'ok_exact',
  'ok_ws',
  'ok_width',
  'ok_joined',
  'ambiguous',
};

/// 「引文锚定」卡级聚合读数（纯函数装配结果）。
class PilotMetricsSummary {
  /// AER 整数百分比（四舍五入）；无引文时 null（调用方出空态文案，不出 0%）。
  final int? aerPercent;

  /// 聚合引文总条数（分母）。
  final int evidenceCount;

  const PilotMetricsSummary({
    required this.aerPercent,
    required this.evidenceCount,
  });
}

/// R-027 文案锚串（设计批 §三 已批五条，逐字；UI 不改写）。
class PilotMetricsText {
  /// ① 卡题（待裁 B 定词：「引文锚定」）
  static const title = '引文锚定';

  /// ② 说明（只陈述 AER 定义，无评价词）
  static const description = '诊断摘出的引文，能在你的原文里找到的比例';

  /// ③ 数值行（{rate}/{count} 代入；count=0 时调用方不出本行）
  static const rateItem = '引文锚定率 {rate}% · 共 {count} 条引文';

  /// ④ 空态（有 anchor_probe 记录但零引文时出；零记录则整卡不渲染）
  static const emptyItem = '暂无引文数据';

  /// ⑤ 隐私注记（口径③「零外发」的诚实注记；不写「安全/保护」等宣传语）
  static const privacyNote = '所有数据只存在本机';

  /// R-009 评价词黑名单（测试断言卡文案不含这些词，B 项同款纪律）。
  static const bannedWords = <String>[
    '进步',
    '掌握',
    '好转',
    '提升',
    '下降',
    '达标',
    '优秀',
    '成功',
    '准确',
    '可靠',
  ];
}

/// 装配「引文锚定」聚合读数（纯函数）。
///
/// 参数：
/// - [anchorPayloads] = anchor_probe 事件的 payload 字符串列表
///   （调用方已按事件类型过滤；停写两类与 app_opened 不进入本函数——
///   设计批裁定④「不读不呈」+ 待裁 A「删」：启动次数行不实施）。
/// - [version] = 当前 payload 协议版本（调用方传 `kAnchorPayloadVersion`）；
///   不符的 payload 按未知版本 **fail-closed 跳过**（不猜未来结构）。
///
/// 返回：
/// - 空列表（零 anchor_probe 记录）⇒ **null** ⇒ 整卡不渲染；
/// - 有记录但聚合零引文 ⇒ summary（aerPercent=null）⇒ 出空态文案④；
/// - 有引文 ⇒ summary（aerPercent=整数百分比）⇒ 出数值行③。
PilotMetricsSummary? buildPilotMetricsSummary(
  List<String> anchorPayloads, {
  required int version,
}) {
  if (anchorPayloads.isEmpty) return null;

  var anchored = 0;
  var total = 0;
  for (final raw in anchorPayloads) {
    final counts = _countAnchored(raw, version: version);
    anchored += counts.anchored;
    total += counts.total;
  }

  return PilotMetricsSummary(
    aerPercent: total == 0 ? null : ((anchored / total) * 100).round(),
    evidenceCount: total,
  );
}

/// 单条 payload 的 (anchored, total) 计数。
///
/// fail-closed 阶梯（任何异常/结构不符 ⇒ 该条不计入，不抛不崩）：
///   非 JSON / 非 Map / 'v' 版本不符 / 'items' 非 List / item 非 Map。
({int anchored, int total}) _countAnchored(String raw, {required int version}) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return (anchored: 0, total: 0);
    if (decoded['v'] != version) return (anchored: 0, total: 0);
    final items = decoded['items'];
    if (items is! List) return (anchored: 0, total: 0);
    var anchored = 0;
    var total = 0;
    for (final item in items) {
      if (item is! Map) continue;
      total++;
      final code = item['k'];
      if (code is String && kAnchoredStatusCodes.contains(code)) {
        anchored++;
      }
    }
    return (anchored: anchored, total: total);
  } catch (_) {
    return (anchored: 0, total: 0);
  }
}
