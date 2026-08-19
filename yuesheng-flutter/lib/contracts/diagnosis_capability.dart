// ─────────────────────────────────────────────────────────────
// 能力契约层 — 诊断能力接口
//
// 架构评审（2026-08-18）选项 A：能力契约层骨架。
// 纯接口定义，不改任何现有实现。UI/编排层只依赖契约，实现可替换。
//
// 当前实现映射：
//   parseDiagnosis      → lib/services/diagnosis_parser.dart
//   validateDiagnosis   → lib/services/diagnosis_validator.dart
//   commitDiagnosis     → lib/services/diagnosis_service.dart
//   parseTrainingResult → lib/services/chat_training_parser.dart
//
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

import '../services/diagnosis_parser.dart';
import '../services/diagnosis_validator.dart';
import '../types/teaching_types.dart';

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
  FullValidationResult validateDiagnosisOutput(
    String displayContent,
    Map<String, dynamic> rawJson,
  );

  /// 从 AI 回复中解析训练结果（passed/partial/failed）。
  /// 纯函数无 IO 依赖。
  TrainingResult? parseTrainingResult(String content);
}
