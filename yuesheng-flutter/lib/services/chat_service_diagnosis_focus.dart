// ─────────────────────────────────────────────────────────────
// chat_service_diagnosis_focus — 诊断焦点相关的纯逻辑（ChatServiceDiagnosisFocus）
//
// ★ B5（2026-10-06）：从 `chat_service.dart` 的 `extension ChatServiceDiagnosisFocus`
//   收敛为独立类（评审 B5 口径：「4 个 extension 逐个收敛为独立类」）。
//
// 为什么是独立类而不是 extension：
//   extension 的存在意义是**跨对象访问私有成员**——它让外部逻辑读写
//   `ChatService` 的下划线成员。本块原先正是靠这个机制拿 `_diagnosisRepo`
//   与 `_logSafeRun`。收敛后改为**构造注入**，依赖显式、可测、可替换。
//
// 依赖注入清单（原 extension 内的隐式依赖 → 显式形参）：
//   `_diagnosisRepo` → diagnosisRepo（构造注入）
//   `_logSafeRun`    → onSafeRun（回调注入；宿主传入其私有实现的引用）
//     ⚠️ 为什么用回调而不是把 `_logSafeRun` 也搬来：它定义在
//        `ChatServiceSend` 块内、被该块 3 处共用，属**共享降级日志设施**
//        （4 处分散实现本仓已登记待抽公用 helper），搬走会破坏那个共用关系。
//        ⇒ 传回调，宿主保持唯一实现。
//
// 零行为变更：方法体逐字迁移，仅 `_diagnosisRepo` → `diagnosisRepo`、
// `_logSafeRun` → `onSafeRun` 两处标识符改名。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../data/repositories/diagnosis_repository.dart';
import '../types/teaching_types.dart';
import 'chat_gates.dart';
import 'intent_classifier.dart';

/// 诊断焦点相关纯逻辑（原 `ChatServiceDiagnosisFocus`）。
class ChatServiceDiagnosisFocus {
  final DiagnosisRepository diagnosisRepo;

  /// 降级留痕回调（宿主传其 `_logSafeRun` 的引用）。
  final void Function(String stage, Object e, StackTrace s) onSafeRun;

  const ChatServiceDiagnosisFocus({
    required this.diagnosisRepo,
    required this.onSafeRun,
  });

  /// 批次1（O1）：Teacher 升级阀——某症候严重度达阈值或诊断次数达阈值时，
  /// 绕过心流窗口（持续写作学员「编辑器活跃 120s」恒真 → 建议永远出不来 →
  /// identified 永不前进 → M4-A 永不满足）。返回 true 时允许建议正常输出。
  Future<bool> shouldBypassFlowWindow(
    String sessionId,
    List<ActiveProblemView> activeProblems,
  ) async {
    if (activeProblems.isEmpty) return false;
    // 严重度阈值：存在 L3 重度症候即绕过
    if (activeProblems.any((p) {
      final sev = Severity.fromString(p.severity);
      return sev != null && sev.index >= kFlowBypassMinSeverity.index;
    })) {
      return true;
    }
    // 诊断次数阈值：某症候累计诊断次数达阈值即绕过（统计失败降级为不绕过）
    // G15：诊断次数唯一口径 = diagnosis_results 全表（confirmed 行按症候聚合），
    // 不再读 teaching_history（后者仅历史流水、全量 append 含 NO_OP 重复）。
    try {
      final diagnosisCounts = await diagnosisRepo
          .countConfirmedDiagnosesBySyndrome(sessionId);
      for (final p in activeProblems) {
        final diagnosisCount = diagnosisCounts[p.syndromeId] ?? 0;
        if (diagnosisCount >= kFlowBypassDiagnosisCount) return true;
      }
    } catch (e, st) {
      onSafeRun('升级阀诊断次数统计失败，降级为不绕过', e, st);
    }
    return false;
  }
}

/// 回复长度观测（原 `ChatServiceObservers`，批次50 临时测量）。
///
/// 该块无任何宿主私有依赖 ⇒ 收敛后**零注入**，是 B5 中成本最低的一块。
class ChatServiceReplyObserver {
  const ChatServiceReplyObserver();

  /// 批次50 临时测量：回复长度观测（standard 档是否真超长）
  /// 「回复颗粒度真人感收敛」决策前置——先量化标准档回复长度分布再决定约束方案。
  /// 仅 debug 级留痕（长度 + 分档 + 颗粒度 + 态度 + 子阶段 + 意图），不改变任何行为；
  /// 批次 52 汇成节奏体检报告后按结论决定保留或删除。观测失败不阻断主流程。
  void observeReplyLength(
    String reply,
    String userInput,
    AttitudeLevel attitude,
    TeachingSubphase? subphase,
  ) {
    if (!kDebugMode) return;
    final len = reply.length;
    String bucket;
    if (len <= 30) {
      bucket = '≤30(一句)';
    } else if (len <= 80) {
      bucket = '31-80(短段)';
    } else if (len <= 160) {
      bucket = '81-160(中段)';
    } else {
      bucket = '>160(长段)';
    }
    final detail = detectReplyDetail(userInput);
    final intent = classifyUserIntent(userInput);
    debugPrint(
      '[批次50 回复长度观测] 长度=$len($bucket) 颗粒度=${detail.value} '
      '态度=${attitude.value} 子阶段=${subphase?.value ?? 'null'} '
      '意图=${intent.value}（仅观测不干预）',
    );
  }
}
