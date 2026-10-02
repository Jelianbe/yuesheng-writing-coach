// ─────────────────────────────────────────────────────────────
// revisit_guardrail — 复刷护栏指标对（ADR-C138 §4.1 / §5.2）
//
// 指标对（研讨 §4.1 表）：复刷率↑ 必须伴随「自主指认率 / 训练深度↑」，
// 否则报警留痕——防止「只回来刷、却没有真指认 / 真训练」的假活跃。
//
// 操作化（ADR §4.1 写死口径）：
//   - 复刷信号 = 同一学员新会话发起（二轮留存/7留口径，tables.dart:952）；
//     由调用方按留存口径判定后以 [isRevisit] 传入，纯函数不查会话表。
//   - 对照窗口 = 上次会话结束 → 本次复刷之间；窗口内事件序列由仓储/查询
//     侧过滤后传入（[windowEvents]），纯函数不查库、不裁时间（R-028 边界
//     在调用方）。
//   - 伴随信号 = 窗口内存在 anchor_ack（自主指认）或 completion（训练完成）。
//   - 报警条件 = 复刷 && 窗口内无任何伴随信号 → 留痕（debugPrint + 事件日志）。
//
// 四硬隔离（R-009，写死）：
//   只记不判 · 不阻断 · 不打分 · 不展示学员。
// 本文件**不做**任何行为干预：判定结果仅供留痕，不回写教学状态、不改 prompt、
// 不进诊断裁决、不展示给学员。纯函数（输入事件序列 → 判定），无 LLM、无 IO。
//
// 文件域纪律：不改 EditDiffEventRepository / 查询工具（C137 并行批消费侧），
// 也不碰写作页；仓储侧取数与真正落事件日志由后续批接线。本文件只交付
// 「输入序列 → 报警判定」的纯函数 + 留痕助手，可脱离 DB 单测。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

/// 窗口内事件类型（只认伴随信号；其余归 [GuardrailEventType.other]）。
///
/// 与 edit_diff_event 表 eventType ∈ {diff, anchor_ack, completion} 对齐：
/// [anchorAck] = 自主指认；[completion] = 成稿/训练完成；[other] = diff 等
/// 非伴随事件（不计入伴随信号）。
enum GuardrailEventType {
  /// 自主指认（学员确认教练指认的片段）。伴随信号之一。
  anchorAck('anchor_ack'),

  /// 成稿 / 训练完成事件。伴随信号之一。
  completion('completion'),

  /// 其余事件（如 diff）：不计入伴随信号。
  other('other');

  final String value;
  const GuardrailEventType(this.value);

  /// 按 edit_diff_event.eventType 字面值映射（未知/空 → [other]，安全降级）。
  static GuardrailEventType fromEventType(String? eventType) {
    switch (eventType) {
      case 'anchor_ack':
        return GuardrailEventType.anchorAck;
      case 'completion':
        return GuardrailEventType.completion;
      default:
        return GuardrailEventType.other;
    }
  }
}

/// 对照窗口内的一条事件（仓储侧已按窗口过滤；纯函数不查库）。
class GuardrailWindowEvent {
  /// 事件类型（伴随信号与否见 [GuardrailEventType]）。
  final GuardrailEventType type;

  const GuardrailWindowEvent({required this.type});
}

/// 护栏判定结果（纯数据，仅供留痕；不传给学员、不参与任何裁决）。
class RevisitGuardrailVerdict {
  /// true = 复刷且窗口内无任何伴随信号 → 应报警留痕。
  final bool shouldAlert;

  /// 窗口内伴随信号计数（anchor_ack + completion；0 = 无伴随）。
  final int companionCount;

  const RevisitGuardrailVerdict({
    required this.shouldAlert,
    required this.companionCount,
  });
}

/// 是否为伴随信号（anchor_ack 自主指认 或 completion 训练完成）。
bool isGuardrailCompanion(GuardrailEventType t) =>
    t == GuardrailEventType.anchorAck || t == GuardrailEventType.completion;

/// 复刷护栏判定（纯函数：无 IO、无 LLM、无副作用、不读全局可变状态）。
///
/// [isRevisit] = 本次是否为同一学员复刷（新会话发起；调用方按二轮留存口径判定）。
/// [windowEvents] = 对照窗口（上次会话结束 → 本次复刷）内的事件序列，已由
///   仓储侧过滤好；纯函数只数其中的伴随信号，不裁时间、不查库。
///
/// 报警条件 = isRevisit && 窗口内伴随信号数为 0。
/// 非复刷 → 一律不报警（首刷/留存观察不在本护栏口径内）。
RevisitGuardrailVerdict evaluateRevisitGuardrail({
  required bool isRevisit,
  required List<GuardrailWindowEvent> windowEvents,
}) {
  if (!isRevisit) {
    // 非复刷：护栏口径外，不报警（companionCount 如实计 0，供审计）。
    return const RevisitGuardrailVerdict(shouldAlert: false, companionCount: 0);
  }
  final n = windowEvents.where((e) => isGuardrailCompanion(e.type)).length;
  return RevisitGuardrailVerdict(shouldAlert: n == 0, companionCount: n);
}

/// 报警留痕（仅 debugPrint；四硬隔离：不阻断 / 不打分 / 不展示学员）。
///
/// 调用方仅在 [RevisitGuardrailVerdict.shouldAlert] == true 时调用。
/// 只打印一行审计信息，不回写教学状态、不改 prompt、不进诊断裁决。
/// 真正落「事件日志表」由后续接线批做（本批只交付纯函数 + 控制台留痕）。
void logRevisitGuardrailAlert(RevisitGuardrailVerdict v) {
  // R-009：措辞不含任何学员可见语义，只供开发者/离线审计。
  debugPrint(
    '[revisit-guardrail] 复刷无伴随信号 → 留痕报警 '
    '(不阻断/不打分/不展示学员): companionCount=${v.companionCount}',
  );
}
