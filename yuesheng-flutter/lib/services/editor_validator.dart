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

  final intents = _validateIntentFields(raw, errors);
  final observations = _validateObservationsField(raw, errors);
  final rest = _validateImpressionAndStrengths(raw, errors);

  if (errors.isNotEmpty) {
    return EditorValidationResult(valid: false, errors: errors);
  }

  return EditorValidationResult(
    valid: true,
    errors: const [],
    data: EditorResult(
      possibleIntent: intents.possibleIntent!,
      intentConfidence: intents.intentConfidence!,
      observations: observations!,
      overallImpression: rest.overallImpression!,
      strengths: rest.strengths!,
    ),
  );
}

/// possible_intent / intent_confidence 校验（R-019 拆出）。
typedef _EditorIntentFields = ({
  String? possibleIntent,
  String? intentConfidence,
});

_EditorIntentFields _validateIntentFields(
  Map<String, dynamic> raw,
  List<EditorValidationError> errors,
) {
  String? possibleIntent;
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

  String? intentConfidence;
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
  return (possibleIntent: possibleIntent, intentConfidence: intentConfidence);
}

/// observations 字段校验（≥3 条 + 逐项解析，R-019 拆出）。
List<EditorObservation>? _validateObservationsField(
  Map<String, dynamic> raw,
  List<EditorValidationError> errors,
) {
  final obsList = raw['observations'];
  if (obsList is! List) {
    errors.add(
      const EditorValidationError(field: 'observations', message: '必须是数组'),
    );
    return null;
  }
  if (obsList.length < 3) {
    errors.add(
      EditorValidationError(
        field: 'observations',
        message: '至少 3 条 observation（实际: ${obsList.length}）',
      ),
    );
    return null;
  }
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
  return ok ? parsedObs : null;
}

/// overall_impression / strengths 校验（R-019 拆出）。
typedef _EditorRestFields = ({
  String? overallImpression,
  List<String>? strengths,
});

_EditorRestFields _validateImpressionAndStrengths(
  Map<String, dynamic> raw,
  List<EditorValidationError> errors,
) {
  String? overallImpression;
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

  List<String>? strengths;
  final st = raw['strengths'];
  if (st is! List) {
    errors.add(
      const EditorValidationError(field: 'strengths', message: '必须是字符串数组'),
    );
  } else if (st.isEmpty) {
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
  return (overallImpression: overallImpression, strengths: strengths);
}

EditorObservation? _parseObservation(
  Map<String, dynamic> map,
  String prefix,
  List<EditorValidationError> errors,
) {
  final dims = _parseDimensionGroup(map, prefix, errors);
  final evidence = _parseEvidenceField(map, prefix, errors);
  final vis = _parseVisibilityGroup(map, prefix, errors);

  if (errors.isNotEmpty) return null;
  return EditorObservation(
    dimension: dims.dimension!,
    dimensionName: dims.dimensionName!,
    phenomenon: dims.phenomenon!,
    evidence: evidence!,
    readerImpact: vis.readerImpact!,
    observationVisibility: vis.observationVisibility!,
    intentAlignment: vis.intentAlignment!,
  );
}

/// dimension / dimension_name / phenomenon 校验（R-019 拆出）。
typedef _ObsDimensionGroup = ({
  String? dimension,
  String? dimensionName,
  String? phenomenon,
});

_ObsDimensionGroup _parseDimensionGroup(
  Map<String, dynamic> map,
  String prefix,
  List<EditorValidationError> errors,
) {
  String? dimension;
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

  String? dimensionName;
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

  String? phenomenon;
  final ph = map['phenomenon'];
  if (ph is String && ph.isNotEmpty) {
    phenomenon = ph;
  } else {
    errors.add(
      EditorValidationError(field: '$prefix.phenomenon', message: '必须是非空字符串'),
    );
  }
  return (
    dimension: dimension,
    dimensionName: dimensionName,
    phenomenon: phenomenon,
  );
}

/// evidence 字段校验（≥1 条 + 逐项，R-019 拆出）。
List<String>? _parseEvidenceField(
  Map<String, dynamic> map,
  String prefix,
  List<EditorValidationError> errors,
) {
  final ev = map['evidence'];
  if (ev is! List) {
    errors.add(
      EditorValidationError(field: '$prefix.evidence', message: '必须是字符串数组'),
    );
    return null;
  }
  if (ev.isEmpty) {
    errors.add(
      EditorValidationError(
        field: '$prefix.evidence',
        message: '至少 1 条 evidence',
      ),
    );
    return null;
  }
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
  return ok ? list : null;
}

/// reader_impact / observation_visibility / intent_alignment 校验（R-019 拆出）。
typedef _ObsVisibilityGroup = ({
  String? readerImpact,
  String? observationVisibility,
  String? intentAlignment,
});

_ObsVisibilityGroup _parseVisibilityGroup(
  Map<String, dynamic> map,
  String prefix,
  List<EditorValidationError> errors,
) {
  String? readerImpact;
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

  final observationVisibility = _parseVisibilityValue(map, prefix, errors);
  final intentAlignment = _parseAlignmentValue(map, prefix, errors);
  return (
    readerImpact: readerImpact,
    observationVisibility: observationVisibility,
    intentAlignment: intentAlignment,
  );
}

/// observation_visibility 白名单校验（R-019 拆出）。
String? _parseVisibilityValue(
  Map<String, dynamic> map,
  String prefix,
  List<EditorValidationError> errors,
) {
  final ov = map['observation_visibility'];
  if (ov is String) {
    if (_isValidVisibility(ov)) {
      return ov;
    }
    errors.add(
      EditorValidationError(
        field: '$prefix.observation_visibility',
        message: '必须是 subtle | moderate | pronounced（实际: $ov）',
      ),
    );
  } else {
    errors.add(
      EditorValidationError(
        field: '$prefix.observation_visibility',
        message: '必填字段',
      ),
    );
  }
  return null;
}

/// intent_alignment 白名单校验（R-019 拆出）。
String? _parseAlignmentValue(
  Map<String, dynamic> map,
  String prefix,
  List<EditorValidationError> errors,
) {
  final ia = map['intent_alignment'];
  if (ia is String) {
    if (_isValidAlignment(ia)) {
      return ia;
    }
    errors.add(
      EditorValidationError(
        field: '$prefix.intent_alignment',
        message: '必须是 aligned | against | unclear（实际: $ia）',
      ),
    );
  } else {
    errors.add(
      EditorValidationError(field: '$prefix.intent_alignment', message: '必填字段'),
    );
  }
  return null;
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
