// ─────────────────────────────────────────────────────────────
// 能力契约层 — 诊断能力接口
//
// 架构评审（2026-08-18）选项 A：能力契约层骨架。
// 选项 B（依赖倒置）：DiagnosisCapability 自持诊断 DTO（ParseResult /
// FullValidationResult / DiagnosisValidationResult / NlValidationResult /
// ValidationError / NlFix），不 import 任何实现文件，避免契约↔实现的
// 循环依赖（门禁 3）。
//
// 实现映射（Dependency Inversion）：
//   class DiagnosisCapabilityImpl (lib/services/diagnosis_parser.dart)
//   implements DiagnosisCapability，委托到既有纯函数
//   parseDiagnosis / validateDiagnosisOutput / parseTrainingResult。
//
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';

/// 校验错误
class ValidationError {
  final String field;
  final String message;
  const ValidationError({required this.field, required this.message});
}

/// JSON schema 校验结果
class DiagnosisValidationResult {
  final bool valid;
  final List<ValidationError> errors;

  /// warning 级提示（互斥症候同命中，不阻断，先观察误伤率）
  final List<String> warnings;
  final Map<String, dynamic>? data;
  const DiagnosisValidationResult({
    required this.valid,
    required this.errors,
    this.warnings = const [],
    this.data,
  });
}

/// 自然语言校验修复项
class NlFix {
  final String type; // V-01 | V-02 | V-03 | V-04
  final String original;
  final String replacement;
  const NlFix({
    required this.type,
    required this.original,
    required this.replacement,
  });
}

/// 自然语言校验结果
class NlValidationResult {
  final bool valid;
  final List<NlFix> fixes;
  final String cleaned;
  const NlValidationResult({
    required this.valid,
    required this.fixes,
    required this.cleaned,
  });
}

/// 完整校验结果
class FullValidationResult {
  final bool passed;
  final String displayContent;
  final ParsedDiagnosis? diagnosis;
  final DiagnosisValidationResult jsonValidation;
  final NlValidationResult nlValidation;
  const FullValidationResult({
    required this.passed,
    required this.displayContent,
    required this.diagnosis,
    required this.jsonValidation,
    required this.nlValidation,
  });
}

/// 诊断解析结果（DTO 上移至契约层，原定义于 diagnosis_parser.dart）
///
/// [rejectReason] / [notes] 为 ADR-C63 新增的可观测性字段（N1 / N26 / N5）。
/// 两者都是**纯附加**——既有字段 [displayContent] / [diagnosis] 的取值在任何
/// 输入下都与新增前逐字节相同，因此全仓既有构造点无需改动。
class ParseResult {
  final String displayContent;
  final ParsedDiagnosis? diagnosis;

  /// 整块被拒的原因码（null = 未被拒）。
  ///
  /// **仅当 AI 确实输出了 `[YS_DIAGNOSIS]` 块、但解析或校验失败时才有值。**
  /// 普通聊天（无块）为 null——这是两件不同的事，不可混淆：
  ///   - 无块且 rejectReason=null → prompt 没生效 / 模型没遵守，要去查 prompt
  ///   - 有块且 rejectReason 有值 → schema 契约问题，要去查字段定义
  /// 混淆二者会把「prompt 未生效」误判成「schema 问题」，或反过来。
  ///
  /// 取值集合见 `diagnosis_parser.dart` 的 `_kRejectReasonDoc`。
  final String? rejectReason;

  /// 非阻断观测码。出现这些码时**整块仍然通过**，行为与无码时完全一致。
  ///
  /// 覆盖两类此前完全静默的情形（N26-B 组 / N5）：
  ///   - `phase_dropped` / `beginner_level_dropped` / `teaching_mode_dropped`：
  ///     可选字段白名单未命中 → 字段被静默置 null，整块照常落库、UI 毫无异样，
  ///     唯独阶段迁移永远不发生。这比整块丢弃更隐蔽。
  ///   - `syndrome_id_format`：`syndrome_id` 不是 `P0xx` 格式（N5）。
  ///     按 ADR-C63 §3.2 **只观测不拦截**——拦截会放大「输出了但不落库」。
  ///
  /// 只记码不记值：值可从原始 `fullContent` 还原，记值会让长文本污染日志。
  final List<String> notes;

  const ParseResult({
    required this.displayContent,
    this.diagnosis,
    this.rejectReason,
    this.notes = const <String>[],
  });
}

/// 诊断能力契约
///
/// 覆盖「AI 回复 → 诊断解析 → 校验 → 落库」链路的纯函数与 IO 操作。
/// UI 层经此契约消费诊断能力，不直接依赖具体实现。
abstract class DiagnosisCapability {
  /// 从 AI 完整回复中提取 [YS_DIAGNOSIS] 块并解析为结构化诊断。
  /// 无标记时返回 displayContent=原文, diagnosis=null。
  ParseResult parseDiagnosis(String rawText);

  /// 对解析出的诊断 JSON 做 schema 校验 + 自然语言修复。
  /// 返回 FullValidationResult（含 JSON 校验 + NL 修复 + 最终诊断）。
  ///
  /// [attitude] 透传到 NL 校验（影响修复策略），与原顶层纯函数签名对齐。
  FullValidationResult validateDiagnosisOutput(
    String displayContent,
    Map<String, dynamic> rawJson, {
    AttitudeLevel? attitude,
  });

  /// 从 AI 回复中解析训练结果（passed/partial/failed）。
  /// 纯函数无 IO 依赖。
  TrainingResult? parseTrainingResult(String content);
}
