// ─────────────────────────────────────────────────────────────
// 发现层出口三「本次未归类」折叠条 payload（S3 · T-20261108-02）。
//
// 授权面 = `.ai/reports/2026-11-08-S3-三态设计稿-报批单.md`（R-027 已批，
// 2026-11-08 舰长「批」）。用户可见文案逐字授权在同单 §四，本文件只做数据面。
//
// 持久化口径（报批单 §一 R3）：
//   · 三态数据随本轮 diagnosis_result 卡片 payload 落库，key = 'discovery'；
//     旧消息 / 短文单次链路无该 key ⇒ 渲染层 S0（折叠条整体不渲染）。
//   · key 只在「本轮诊断实际走到发现层」时落：分块链路（>4000 字）的
//     onDiscovery 恰广播 1 次（progressive_diagnosis.dart:1161，gate=null
//     也广播 empty）⇒ configured=false 也要落 key（否则态①丢失）。
//   · 只持久化出口三（unclassified）的 reason + anchorQuotes；出口二
//     （observation）留作内部审计（舰长已裁「只出口三」）；promoted /
//     dropped 等分母字段不进用户面 payload。
//
// 零依赖面：只 import discovery_note.dart（其本身零依赖），不反向依赖
// 验证层与 UI 层 —— 与 discovery_note.dart 的零依赖纪律同构。
// ─────────────────────────────────────────────────────────────

import 'discovery_note.dart';

/// 折叠条逐条数据（出口三一条 = 一个 item）。
class DiscoveryNoteCard {
  final String reason;

  /// 原句锚点（协议强约束 ≥1，已过 chunk.contains 子串校验）。
  final List<String> anchorQuotes;

  const DiscoveryNoteCard({required this.reason, this.anchorQuotes = const []});

  factory DiscoveryNoteCard.fromJson(Map<String, dynamic> json) {
    return DiscoveryNoteCard(
      reason: (json['reason'] as String?) ?? '',
      anchorQuotes:
          (json['anchorQuotes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'reason': reason,
    'anchorQuotes': anchorQuotes,
  };
}

/// 折叠条三态数据（payload 'discovery' key 的形态）。
class DiscoverySectionCard {
  /// 本轮发现层是否启用（= 该轮传入 runProgressiveDiagnosis 的
  /// verificationGate != null 的轮次快照，随卡片落库，渲染时不再回读存储）。
  /// false ⇒ 渲染态①（验证层未启用）。
  final bool configured;

  /// 出口三条目（映射时已过滤 promoted / observation）。
  /// configured 且空列表 ⇒ 态②（本次全部已归类）。
  final List<DiscoveryNoteCard> unclassified;

  const DiscoverySectionCard({
    required this.configured,
    this.unclassified = const [],
  });

  factory DiscoverySectionCard.fromJson(Map<String, dynamic> json) {
    return DiscoverySectionCard(
      configured: (json['configured'] as bool?) ?? false,
      unclassified:
          (json['unclassified'] as List<dynamic>?)
              ?.map(
                (e) => DiscoveryNoteCard.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'configured': configured,
    // 空列表不落 key（与 focusCandidates 同款往返稳定约定；
    // fromJson 侧 null 与空列表都归一为「无条目」）。
    if (unclassified.isNotEmpty)
      'unclassified': unclassified.map((n) => n.toJson()).toList(),
  };
}

/// 轮次产物 → 折叠条 payload（两链 controller 共用的唯一映射行）。
///
/// result == null（本轮没走到发现层：短文单次链路 / 旧轮）⇒ null ⇒ 落库
/// 不落 key ⇒ 渲染层 S0。result 非空 ⇒ 一律落 key：configured 快照 =
/// 该轮 gate 是否非空；gate 非空但 fail-closed 回 empty 的轮次归态②
/// （UI 拿不到失败信号，不伪造失败提示 —— 报批单 §二 E6）。
DiscoverySectionCard? discoverySectionOf(
  bool configured,
  DiscoveryParseResult? result,
) {
  if (result == null) return null;
  return DiscoverySectionCard(
    configured: configured,
    unclassified: result.notes
        .where((n) => n.exit == DiscoveryExit.unclassified)
        .map(
          (n) =>
              DiscoveryNoteCard(reason: n.reason, anchorQuotes: n.anchorQuotes),
        )
        .toList(),
  );
}
