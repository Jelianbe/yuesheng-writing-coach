// ─────────────────────────────────────────────────────────────
// diagnosis_failure_tracker — 诊断连续失败计数 + 失败卡 + 原因留痕
//
// 【为什么独立成类，而不是留在 DiagnosisFlowHandler 里】
//   ① **行数硬约束**：`diagnosis_flow_handler.dart` 已是 1820 行的存量超限文件，
//      门禁 5 的文件级判据（≤300 行，基线模式下**变胖容差 0 行**）不允许再加行。
//      本轮 A2 若把「计数 + 落日志 + 插卡」三件事内联回 handler，实测 +70 行 ⇒ 直接红。
//   ② **架构方向一致**：`tool/split_shape_baseline.json` 的 `plannedMigrations`
//      已为 handler 登记 U7「分阶段真分解（ADR-0004 R-3 独立类 + DI，不硬拆）」。
//      本类正是该方向的一步，**不是**用 extension / part 伪拆分。
//   ③ **状态可测**：计数 Map 此前是 handler 的私有字段，外部无法观测也无人能单测。
//      搬成独立类后可注入假 SessionRepository 直接断言「第几次失败插卡」。
//
// 【行为口径：零变化（这是本轮最重要的保证）】
//   · `success` 口径仍是 `diagnosis != null`，由调用方传入，本类**不重新判定**；
//   · 计数语义不变：`attempted && !success` 才 +1，成功清零，非诊断轮次不动；
//   · 失败卡插入时机不变：**每次**失败都插（首次也插），失败不影响主流程；
//   · `empty_match`（解析成功但零症候）**只观测、不计失败** —— 这是 A2 新增的
//     可见性，不改判定：它仍是成功（模型有效输出）。
// ─────────────────────────────────────────────────────────────

// 字段私有（_sessionRepo）+ 构造参数公开名（sessionRepo）是刻意的：
// 调用方不该看见下划线前缀，而字段不该公开。二者无法用 this._x 合并。
// ignore_for_file: prefer_initializing_formals

import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/diagnosis_failure_reason.dart';
import 'package:writingcoach/services/message_card_service.dart'
    show insertDiagnosisFailedCard;

/// 诊断失败跟踪器（B1 阈值门控 + A2 原因留痕）。
///
/// 由 `DiagnosisFlowHandler` 持有并委托；**不引入新依赖方向**
/// （只依赖 SessionRepository 与既有两个顶层函数）。
class DiagnosisFailureTracker {
  DiagnosisFailureTracker({required SessionRepository sessionRepo})
    : _sessionRepo = sessionRepo;

  final SessionRepository _sessionRepo;

  /// 连续失败计数（按 session 隔离；普通聊天不计入）。
  ///
  /// **每次**失败都插卡（首次也不例外）：否则用户只看到流式正文结束，
  /// 分不清「还在写」与「已失败」。卡内「额外提示」阈值仍由
  /// `UILimits.failureWarningThreshold` 在 widget 侧判（`diagnosis_failed_card.dart:83`）。
  final Map<String, int> _consecutiveFails = {};

  /// 读当前连续失败次数（测试与排查用；生产路径不依赖）。
  int consecutiveFailsOf(String sessionId) => _consecutiveFails[sessionId] ?? 0;

  /// 记录一轮诊断结果。
  ///
  /// [attempted] 表示该轮是否确实发起了诊断（AI 输出含 `[YS_DIAGNOSIS]` 块，
  /// 或走显式诊断链路 `commitDiagnosisFromContent`）。仅当 `attempted && !success`
  /// 才计为一次失败，普通聊天（解析为 null）不会误触发。
  ///
  /// [rejectReason] / [syndromeCount] 是 A2 新增的**可选**入参，只为让失败原因
  /// 落进内部日志；传参缺失 ⇒ 行为与改造前完全一致。
  Future<void> record({
    required String sessionId,
    required bool attempted,
    required bool success,
    String? rejectReason,
    int? syndromeCount,
    void Function(String stage, Object e, StackTrace s)? onInsertFailed,
  }) async {
    if (!attempted) return; // 非诊断轮次：不动计数
    final reason = classifyParseOutcome(
      rejectReason: rejectReason,
      syndromeCount: syndromeCount,
    );
    if (success) {
      _consecutiveFails[sessionId] = 0;
      // A2：解析通过但一条症候都没匹配到 —— **只观测不计失败**（判定口径不变）。
      if (reason != null) {
        _log(sessionId: sessionId, reason: reason, path: 'parse');
      }
      return;
    }
    final count = (_consecutiveFails[sessionId] ?? 0) + 1;
    _consecutiveFails[sessionId] = count;
    _log(
      sessionId: sessionId,
      reason: reason ?? kDiagnosisFailureUnknown,
      path: 'parse',
      failureCount: count,
      detail: rejectReason,
      syndromeCount: syndromeCount,
    );
    try {
      await insertDiagnosisFailedCard(_sessionRepo, sessionId, count);
    } catch (e, s) {
      // 插卡失败不阻断主流程（原逻辑一字未改：由调用方决定如何留痕）。
      onInsertFailed?.call('诊断失败卡插入失败不阻断主流程', e, s);
    }
  }

  /// 落库留痕（形状真源在 `diagnosis_failure_reason.dart`，发送侧共用）。
  void _log({
    required String sessionId,
    required String reason,
    required String path,
    int? failureCount,
    String? detail,
    int? syndromeCount,
  }) {
    recordDiagnosisFailureLog(
      reason: reason,
      path: path,
      failureCount: failureCount,
      detail: detail,
      syndromeCount: syndromeCount,
      hasSession: sessionId.isNotEmpty,
    );
  }
}
