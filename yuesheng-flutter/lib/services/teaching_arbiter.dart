// ─────────────────────────────────────────────────────────────
// teaching_arbiter — 五阀联动编排层（D3 批落地；H6 动作2 阀1 启用）
//
// 职责：把原本散落在 message_injector / diagnosis_flow_handler /
// message_assembly_service 的 5 阀调用收成一条显式管线，统一调用入口。
//
// ★ H6 动作2（2026-10-14 舰长批准启用）：阀 1 起真闸门——
//   shouldTriggerTeacherForDiagnosis=false（活跃症候无 L2/L3 且总数 <3）
//   ⇒ 跳过阀 2/阀 3：本轮不解析教学焦点（activatedFocusId=null，症候段
//   退为概览注入）、不构造训练输入（trainingInput=null，训练 FSM 不注入）。
//   shouldTeach=true 时行为与 D3 批完全一致。
//   阀 1 判据本身 = chat_gates 既有阈值，本批零改动。
//
// 5 阀联动顺序：
//   1. shouldTriggerTeacherForDiagnosis(syndromes) —— 闸门（H6 动作2 启用）
//   2. resolveTeachingFocus(focusInput) —— 教哪个（输出 activatedFocusId）
//   3. buildTrainingInputForActiveSyndrome(...) —— 怎么教（输出 trainingInput）
//   ※ isInFlow / shouldBypassFlowWindow 由 message_assembly_service 调用，
//     结果通过 flowBypassed / rapidFire 参数传入 arbiter（trace 用，
//     当前不参与注入决策；D3.5/D7 决定是否启用闸门）
// ─────────────────────────────────────────────────────────────

library;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/student_model_repository.dart';
import '../types/teaching_types.dart';
import 'chat_gates.dart';
import 'focus_resolver.dart';
import 'training_evaluator.dart';
import 'training_input_builder.dart';

/// arbiter 输入（编排五阀所需上下文）
class ArbitrationInput {
  /// 用于 shouldTriggerTeacherForDiagnosis（H6 动作2：真闸门）
  final List<Syndrome> syndromes;

  /// 用于 resolveTeachingFocus（教哪个）
  final ResolveFocusInput focusInput;

  /// 用于 buildTrainingInputForActiveSyndrome（怎么教）
  final StudentModelRepository studentModelRepo;
  final String sessionId;

  /// active_problem 全表（arbiter 用 activatedFocusId 在此查
  /// 对应条目构造 [ActiveProblemMeta]；查不到 ⇒ trainingInput=null）
  final List<ActiveProblemView> activeProblems;

  /// v19：传 DiagnosisRepo 让 startingTeachingState 优先读持久化起点
  final DiagnosisRepository? diagnosisRepo;

  /// 心流窗口结果（由 message_assembly_service.resolveFlowWindow 调
  /// isInFlow / shouldBypassFlowWindow 后传入；当前仅 trace，不参与注入决策）
  final bool flowBypassed;

  /// 心流窗口的 rapidFire 输入（同上，仅 trace）
  final bool rapidFire;

  const ArbitrationInput({
    required this.syndromes,
    required this.focusInput,
    required this.studentModelRepo,
    required this.sessionId,
    required this.activeProblems,
    this.diagnosisRepo,
    this.flowBypassed = false,
    this.rapidFire = false,
  });
}

/// arbiter 输出（编排结果 + trace）
class ArbitrationResult {
  /// 阀 2 完整输出（含 activatedFocusId / source / reason / rejectReason）
  ///
  /// 调用方按需取字段：
  ///   - `result.focusOutput.activatedFocusId` —— 教哪个
  ///   - `result.focusOutput.source` / `reason` / `rejectReason`
  final ResolveFocusOutput focusOutput;

  /// 来自 buildTrainingInputForActiveSyndrome（怎么教）
  final EvaluationSummaryInput? trainingInput;

  /// 来自 shouldTriggerTeacherForDiagnosis（H6 动作2 起为真闸门判定）
  ///
  /// false ⇒ focusOutput 为「未激活」占位（activatedFocusId=null）、
  /// trainingInput=null，阀 2/阀 3 不调用
  final bool shouldTeach;

  /// 调试用 trace（每阀调用结果按顺序记录）
  final List<String> arbitrationTrace;

  const ArbitrationResult({
    required this.focusOutput,
    required this.trainingInput,
    required this.shouldTeach,
    required this.arbitrationTrace,
  });
}

/// 五阀联动编排入口（D3 批；H6 动作2 起阀 1 为真闸门）
///
/// 调用顺序：
///   1. shouldTriggerTeacherForDiagnosis → shouldTeach（H6 动作2：闸门）
///   2. resolveTeachingFocus → 取 activatedFocusId（仅 shouldTeach=true）
///   3. buildTrainingInputForActiveSyndrome → 取 trainingInput（仅 shouldTeach=true）
///
/// shouldTeach=false ⇒ 跳过 #2 #3（activatedFocusId=null / trainingInput=null）
Future<ArbitrationResult> arbitrate(ArbitrationInput input) async {
  final trace = <String>[];
  final shouldTeach = _evaluateShouldTeach(input.syndromes, trace);
  // H6 动作2（2026-10-14 舰长批准启用）：阀 1 闸门生效。
  if (!shouldTeach) {
    _appendTrace(trace, '阀1 闸门生效：shouldTeach=false ⇒ 跳过阀2/阀3');
    return ArbitrationResult(
      focusOutput: const ResolveFocusOutput(
        activatedFocusId: null,
        source: FocusSource.none,
        reason:
            '阀1 闸门：活跃症候未达教学触发条件（无 L2/L3 且总数 <3），'
            '本轮不激活教学焦点',
      ),
      trainingInput: null,
      shouldTeach: false,
      arbitrationTrace: trace,
    );
  }
  final focusOutput = _resolveActivatedFocus(input.focusInput, trace);
  final trainingInput = await _buildTrainingInput(
    focusOutput.activatedFocusId,
    input,
    trace,
  );
  return ArbitrationResult(
    focusOutput: focusOutput,
    trainingInput: trainingInput,
    shouldTeach: shouldTeach,
    arbitrationTrace: trace,
  );
}

/// 阀 1：shouldTriggerTeacherForDiagnosis（H6 动作2：闸门）
bool _evaluateShouldTeach(List<Syndrome> syndromes, List<String> trace) {
  final shouldTeach = shouldTriggerTeacherForDiagnosis(syndromes);
  _appendTrace(trace, '阀1 shouldTriggerTeacherForDiagnosis=$shouldTeach');
  return shouldTeach;
}

/// 阀 2：resolveTeachingFocus（输出 activatedFocusId）
ResolveFocusOutput _resolveActivatedFocus(
  ResolveFocusInput focusInput,
  List<String> trace,
) {
  final output = resolveTeachingFocus(focusInput);
  _appendTrace(
    trace,
    '阀2 resolveTeachingFocus: activatedFocusId=${output.activatedFocusId} '
    'source=${output.source.value} reason=${output.reason}',
  );
  return output;
}

/// 阀 3：buildTrainingInputForActiveSyndrome（输出 trainingInput）
///
/// activatedFocusId 为空 / 在 activeProblems 中找不到对应条目时跳过
/// （与现行 message_injector 行为一致）
Future<EvaluationSummaryInput?> _buildTrainingInput(
  String? activatedFocusId,
  ArbitrationInput input,
  List<String> trace,
) async {
  if (activatedFocusId == null) {
    _appendTrace(trace, '阀3 跳过：activatedFocusId 为空');
    return null;
  }
  final meta = _resolveActiveProblemMeta(
    activatedFocusId,
    input.activeProblems,
  );
  if (meta == null) {
    _appendTrace(trace, '阀3 跳过：activeProblems 中无 $activatedFocusId');
    return null;
  }
  final trainingInput = await buildTrainingInputForActiveSyndrome(
    input.studentModelRepo,
    input.sessionId,
    activatedFocusId,
    meta,
    diagnosisRepo: input.diagnosisRepo,
  );
  _appendTrace(
    trace,
    '阀3 buildTrainingInputForActiveSyndrome: '
    'trainingInput=${trainingInput != null ? "非空" : "null"}',
  );
  return trainingInput;
}

/// 由 activatedFocusId 在 activeProblems 中查对应 [ActiveProblemMeta]
/// （复刻 message_injector._injectTrainingFsmAndContext 行 1967-1970 的构造逻辑）
ActiveProblemMeta? _resolveActiveProblemMeta(
  String activatedFocusId,
  List<ActiveProblemView> activeProblems,
) {
  for (final p in activeProblems) {
    if (p.syndromeId == activatedFocusId) {
      return ActiveProblemMeta(
        currentSeverity: Severity.fromString(p.severity) ?? Severity.l2,
      );
    }
  }
  return null;
}

/// trace 追加 helper（仅 kDebugMode 输出，避免生产日志噪音）
void _appendTrace(List<String> trace, String message) {
  trace.add(message);
  if (kDebugMode) debugPrint('[TeachingArbiter] $message');
}
