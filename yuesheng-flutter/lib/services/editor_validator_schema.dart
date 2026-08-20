// ─────────────────────────────────────────────────────────────
// editor_validator 拆分：editor_validator_schema.dart（R-019 ≤300 行）
// Schema 校验：validateEditorSchema/_parseObservation。迁移自 editor_validator.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'editor_validator.dart';
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

