// ─────────────────────────────────────────────────────────────
// Editor Observation Validator
// 复刻 yuesheng-android/src/services/editor-validator.ts
//
// Schema 校验 + 硬限制（判决词检测，防止 Editor 变诊断器）。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/config/shared_constants.dart';

part 'editor_validator_schema.dart';
part 'editor_validator_limits.dart';
// ─── 维度/级别常量 ────────────────────────────────────────────

const List<String> kEditorDimensions = [
  'character_agency',
  'character_depth',
  'pacing_control',
  'conflict_dynamics',
  'narrative_turn',
  'theme_expression',
  'plot_mechanics',
  'world_consistency',
  'dialogue_dynamics',
];

const List<String> kVisibilityLevels = ['subtle', 'moderate', 'pronounced'];
const List<String> kIntentAlignments = ['aligned', 'against', 'unclear'];
const List<String> kIntentConfidences = ['low', 'moderate', 'high'];

bool _isValidDimension(String s) => kEditorDimensions.contains(s);
bool _isValidVisibility(String s) => kVisibilityLevels.contains(s);
bool _isValidAlignment(String s) => kIntentAlignments.contains(s);
bool _isValidConfidence(String s) => kIntentConfidences.contains(s);

// ─── 类型 ──────────────────────────────────────────────────────

class EditorObservation {
  final String dimension;
  final String dimensionName;
  final String phenomenon;
  final List<String> evidence;
  final String readerImpact;
  final String observationVisibility;
  final String intentAlignment;

  const EditorObservation({
    required this.dimension,
    required this.dimensionName,
    required this.phenomenon,
    required this.evidence,
    required this.readerImpact,
    required this.observationVisibility,
    required this.intentAlignment,
  });
}

class EditorResult {
  final String possibleIntent;
  final String intentConfidence;
  final List<EditorObservation> observations;
  final String overallImpression;
  final List<String> strengths;

  const EditorResult({
    required this.possibleIntent,
    required this.intentConfidence,
    required this.observations,
    required this.overallImpression,
    required this.strengths,
  });
}

class EditorValidationError {
  final String field;
  final String message;
  const EditorValidationError({required this.field, required this.message});
}

class EditorValidationResult {
  final bool valid;
  final List<EditorValidationError> errors;
  final EditorResult? data;
  const EditorValidationResult({
    required this.valid,
    required this.errors,
    this.data,
  });
}

class HardLimitViolation {
  final String dimension;
  final String field;
  final List<String> verdictWords;
  const HardLimitViolation({
    required this.dimension,
    required this.field,
    required this.verdictWords,
  });
}

class HardLimitResult {
  final bool passed;
  final List<HardLimitViolation> violations;
  const HardLimitResult({required this.passed, required this.violations});
}

class FullEditorValidationResult {
  final bool passed;
  final EditorValidationResult schemaValidation;
  final HardLimitResult hardLimit;
  final EditorResult? data;
  const FullEditorValidationResult({
    required this.passed,
    required this.schemaValidation,
    required this.hardLimit,
    this.data,
  });
}

// ─── 判决词检测 ────────────────────────────────────────────────

/// 检查单条文本是否含判决词。返回命中数组。
List<String> detectVerdictWords(String text) {
  final hits = <String>[];
  for (final word in verdictDangerousWords) {
    if (text.contains(word)) hits.add(word);
  }
  return hits;
}
