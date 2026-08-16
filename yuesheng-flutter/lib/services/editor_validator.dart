// ─────────────────────────────────────────────────────────────
// Editor Observation Validator
// 复刻 yuesheng-android/src/services/editor-validator.ts
//
// Schema 校验 + 硬限制（判决词检测，防止 Editor 变诊断器）。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/config/shared_constants.dart';

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

// ─── Schema 校验 ───────────────────────────────────────────────

EditorValidationResult validateEditorSchema(Object? raw) {
  final errors = <EditorValidationError>[];
  if (raw is! Map<String, dynamic>) {
    return EditorValidationResult(
      valid: false,
      errors: const [
        EditorValidationError(field: '<root>', message: '必须是 JSON 对象'),
      ],
    );
  }

  String? possibleIntent;
  String? intentConfidence;
  List<EditorObservation>? observations;
  String? overallImpression;
  List<String>? strengths;

  // possible_intent
  final pi = raw['possible_intent'];
  if (pi is String && pi.isNotEmpty) {
    possibleIntent = pi;
  } else {
    errors.add(
      const EditorValidationError(
        field: 'possible_intent',
        message: '必须是非空字符串',
      ),
    );
  }

  // intent_confidence
  final ic = raw['intent_confidence'];
  if (ic is String) {
    if (_isValidConfidence(ic)) {
      intentConfidence = ic;
    } else {
      errors.add(
        EditorValidationError(
          field: 'intent_confidence',
          message: '必须是 low | moderate | high（实际: $ic）',
        ),
      );
    }
  } else {
    errors.add(
      const EditorValidationError(field: 'intent_confidence', message: '必填字段'),
    );
  }

  // observations
  final obsList = raw['observations'];
  if (obsList is List) {
    if (obsList.length < 3) {
      errors.add(
        EditorValidationError(
          field: 'observations',
          message: '至少 3 条 observation（实际: ${obsList.length}）',
        ),
      );
    } else {
      final parsedObs = <EditorObservation>[];
      bool ok = true;
      for (int i = 0; i < obsList.length; i++) {
        final item = obsList[i];
        if (item is! Map) {
          errors.add(
            EditorValidationError(field: 'observations[$i]', message: '必须是对象'),
          );
          ok = false;
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        final o = _parseObservation(map, 'observations[$i]', errors);
        if (o != null) {
          parsedObs.add(o);
        } else {
          ok = false;
        }
      }
      if (ok) observations = parsedObs;
    }
  } else {
    errors.add(
      const EditorValidationError(field: 'observations', message: '必须是数组'),
    );
  }

  // overall_impression
  final oi = raw['overall_impression'];
  if (oi is String && oi.isNotEmpty) {
    overallImpression = oi;
  } else {
    errors.add(
      const EditorValidationError(
        field: 'overall_impression',
        message: '必须是非空字符串',
      ),
    );
  }

  // strengths
  final st = raw['strengths'];
  if (st is List) {
    if (st.isEmpty) {
      errors.add(
        const EditorValidationError(field: 'strengths', message: '至少 1 条'),
      );
    } else {
      final list = <String>[];
      bool ok = true;
      for (int i = 0; i < st.length; i++) {
        final item = st[i];
        if (item is String && item.isNotEmpty) {
          list.add(item);
        } else {
          errors.add(
            EditorValidationError(field: 'strengths[$i]', message: '必须是非空字符串'),
          );
          ok = false;
        }
      }
      if (ok) strengths = list;
    }
  } else {
    errors.add(
      const EditorValidationError(field: 'strengths', message: '必须是字符串数组'),
    );
  }

  if (errors.isNotEmpty) {
    return EditorValidationResult(valid: false, errors: errors);
  }

  return EditorValidationResult(
    valid: true,
    errors: const [],
    data: EditorResult(
      possibleIntent: possibleIntent!,
      intentConfidence: intentConfidence!,
      observations: observations!,
      overallImpression: overallImpression!,
      strengths: strengths!,
    ),
  );
}

EditorObservation? _parseObservation(
  Map<String, dynamic> map,
  String prefix,
  List<EditorValidationError> errors,
) {
  String? dimension;
  String? dimensionName;
  String? phenomenon;
  List<String>? evidence;
  String? readerImpact;
  String? observationVisibility;
  String? intentAlignment;

  final d = map['dimension'];
  if (d is String && _isValidDimension(d)) {
    dimension = d;
  } else {
    errors.add(
      EditorValidationError(
        field: '$prefix.dimension',
        message: d is String ? '非法维度（实际: $d）' : 'dimension 必填',
      ),
    );
  }

  final dn = map['dimension_name'];
  if (dn is String && dn.isNotEmpty) {
    dimensionName = dn;
  } else {
    errors.add(
      EditorValidationError(
        field: '$prefix.dimension_name',
        message: '必须是非空字符串',
      ),
    );
  }

  final ph = map['phenomenon'];
  if (ph is String && ph.isNotEmpty) {
    phenomenon = ph;
  } else {
    errors.add(
      EditorValidationError(field: '$prefix.phenomenon', message: '必须是非空字符串'),
    );
  }

  final ev = map['evidence'];
  if (ev is List) {
    if (ev.isEmpty) {
      errors.add(
        EditorValidationError(
          field: '$prefix.evidence',
          message: '至少 1 条 evidence',
        ),
      );
    } else {
      final list = <String>[];
      bool ok = true;
      for (int i = 0; i < ev.length; i++) {
        final item = ev[i];
        if (item is String && item.isNotEmpty) {
          list.add(item);
        } else {
          errors.add(
            EditorValidationError(
              field: '$prefix.evidence[$i]',
              message: '必须是非空字符串',
            ),
          );
          ok = false;
        }
      }
      if (ok) evidence = list;
    }
  } else {
    errors.add(
      EditorValidationError(field: '$prefix.evidence', message: '必须是字符串数组'),
    );
  }

  final ri = map['reader_impact'];
  if (ri is String && ri.isNotEmpty) {
    readerImpact = ri;
  } else {
    errors.add(
      EditorValidationError(
        field: '$prefix.reader_impact',
        message: '必须是非空字符串',
      ),
    );
  }

  final ov = map['observation_visibility'];
  if (ov is String) {
    if (_isValidVisibility(ov)) {
      observationVisibility = ov;
    } else {
      errors.add(
        EditorValidationError(
          field: '$prefix.observation_visibility',
          message: '必须是 subtle | moderate | pronounced（实际: $ov）',
        ),
      );
    }
  } else {
    errors.add(
      EditorValidationError(
        field: '$prefix.observation_visibility',
        message: '必填字段',
      ),
    );
  }

  final ia = map['intent_alignment'];
  if (ia is String) {
    if (_isValidAlignment(ia)) {
      intentAlignment = ia;
    } else {
      errors.add(
        EditorValidationError(
          field: '$prefix.intent_alignment',
          message: '必须是 aligned | against | unclear（实际: $ia）',
        ),
      );
    }
  } else {
    errors.add(
      EditorValidationError(field: '$prefix.intent_alignment', message: '必填字段'),
    );
  }

  if (errors.isNotEmpty) return null;
  return EditorObservation(
    dimension: dimension!,
    dimensionName: dimensionName!,
    phenomenon: phenomenon!,
    evidence: evidence!,
    readerImpact: readerImpact!,
    observationVisibility: observationVisibility!,
    intentAlignment: intentAlignment!,
  );
}

// ─── 硬限制检查 ────────────────────────────────────────────────

HardLimitResult checkHardLimits(EditorResult result) {
  final violations = <HardLimitViolation>[];
  for (final obs in result.observations) {
    final phHits = detectVerdictWords(obs.phenomenon);
    if (phHits.isNotEmpty) {
      violations.add(
        HardLimitViolation(
          dimension: obs.dimension,
          field: 'phenomenon',
          verdictWords: phHits,
        ),
      );
    }
    final riHits = detectVerdictWords(obs.readerImpact);
    if (riHits.isNotEmpty) {
      violations.add(
        HardLimitViolation(
          dimension: obs.dimension,
          field: 'reader_impact',
          verdictWords: riHits,
        ),
      );
    }
  }
  return HardLimitResult(passed: violations.isEmpty, violations: violations);
}

// ─── 完整校验入口 ──────────────────────────────────────────────

FullEditorValidationResult validateEditorOutput(Object? raw) {
  final schemaValidation = validateEditorSchema(raw);
  if (!schemaValidation.valid || schemaValidation.data == null) {
    return FullEditorValidationResult(
      passed: false,
      schemaValidation: schemaValidation,
      hardLimit: const HardLimitResult(passed: true, violations: []),
    );
  }
  final hardLimit = checkHardLimits(schemaValidation.data!);
  return FullEditorValidationResult(
    passed: hardLimit.passed,
    schemaValidation: schemaValidation,
    hardLimit: hardLimit,
    data: hardLimit.passed ? schemaValidation.data : null,
  );
}

// ─── 格式化 ────────────────────────────────────────────────────

String formatEditorErrors(FullEditorValidationResult result) {
  final parts = <String>[];
  if (!result.schemaValidation.valid) {
    parts.add('[Schema 校验] ${result.schemaValidation.errors.length} 个错误:');
    for (final e in result.schemaValidation.errors) {
      parts.add('  - ${e.field}: ${e.message}');
    }
  }
  if (!result.hardLimit.passed) {
    parts.add('[硬限制] ${result.hardLimit.violations.length} 个判决词违规:');
    for (final v in result.hardLimit.violations) {
      parts.add(
        '  - ${v.dimension}.${v.field}: 含判决词 [${v.verdictWords.join(', ')}]',
      );
    }
  }
  return parts.join('\n');
}
