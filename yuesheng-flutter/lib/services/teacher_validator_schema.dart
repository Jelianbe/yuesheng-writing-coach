// ─────────────────────────────────────────────────────────────
// teacher_validator 主题分组拆分：teacher_validator_schema.dart（R-019 ≤300 行）
// 检测函数（detectTeacherVerdictWords/detectSyndromeIdLeak）+ validateTeacherSchema/_parseTrainingTask。逐字迁移自 teacher_validator.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'teacher_validator.dart';
// ─── 检测函数 ──────────────────────────────────────────────────

List<String> detectTeacherVerdictWords(String text) {
  final hits = <String>[];
  for (final word in verdictDangerousWords) {
    if (text.contains(word)) hits.add(word);
  }
  return hits;
}

List<String> detectSyndromeIdLeak(String text) {
  return _syndromeIdPattern.allMatches(text).map((m) => m.group(0)!).toList();
}

// ─── Schema 校验 ───────────────────────────────────────────────

TeacherValidationResult validateTeacherSchema(Object? raw) {
  final errors = <TeacherValidationError>[];
  if (raw is! Map<String, dynamic>) {
    return TeacherValidationResult(
      valid: false,
      errors: const [
        TeacherValidationError(field: '<root>', message: '必须是 JSON 对象'),
      ],
    );
  }

  String? teachingDecision;
  String? teachingReason;
  String? naturalLanguage;
  TrainingTask? trainingTask;

  // teaching_decision
  final td = raw['teaching_decision'];
  if (td is String) {
    if (_isValidDecision(td)) {
      teachingDecision = td;
    } else {
      errors.add(
        TeacherValidationError(
          field: 'teaching_decision',
          message: '必须是 encourage | guide | train | defer（实际: $td）',
        ),
      );
    }
  } else {
    errors.add(
      const TeacherValidationError(field: 'teaching_decision', message: '必填字段'),
    );
  }

  // teaching_reason
  final tr = raw['teaching_reason'];
  if (tr is String && tr.isNotEmpty) {
    teachingReason = tr;
  } else {
    errors.add(
      const TeacherValidationError(
        field: 'teaching_reason',
        message: '必须是非空字符串',
      ),
    );
  }

  // natural_language
  final nl = raw['natural_language'];
  if (nl is String && nl.isNotEmpty) {
    naturalLanguage = nl;
  } else {
    errors.add(
      const TeacherValidationError(
        field: 'natural_language',
        message: '必须是非空字符串',
      ),
    );
  }

  // training_task（optional，但如果存在必须是对象，且字段有效）
  final tt = raw['training_task'];
  if (tt != null) {
    if (tt is Map) {
      final map = Map<String, dynamic>.from(tt);
      final parsed = _parseTrainingTask(map, 'training_task', errors);
      if (parsed != null) trainingTask = parsed;
    } else {
      errors.add(
        const TeacherValidationError(
          field: 'training_task',
          message: '必须是对象或省略',
        ),
      );
    }
  }

  // location_marks（optional，批次63 B62d）——宽松解析：
  // 合法字符串数组 → 采纳；缺失或非法 → 静默忽略（可选字段不阻断整条建议）
  List<String> locationMarks = const [];
  final lm = raw['location_marks'];
  if (lm is List) {
    final list = <String>[];
    var ok = true;
    for (final item in lm) {
      if (item is String && item.isNotEmpty) {
        list.add(item);
      } else {
        ok = false;
        break;
      }
    }
    if (ok) locationMarks = list;
  }

  if (errors.isNotEmpty) {
    return TeacherValidationResult(valid: false, errors: errors);
  }

  return TeacherValidationResult(
    valid: true,
    errors: const [],
    data: TeacherResult(
      teachingDecision: teachingDecision!,
      teachingReason: teachingReason!,
      naturalLanguage: naturalLanguage!,
      trainingTask: trainingTask,
      locationMarks: locationMarks,
    ),
  );
}

TrainingTask? _parseTrainingTask(
  Map<String, dynamic> map,
  String prefix,
  List<TeacherValidationError> errors,
) {
  String? targetSyndromeId;
  String? targetDimension;
  String? taskType;
  String? taskDescription;
  String? difficulty;
  List<String>? evaluationCriteria;

  // target_syndrome_id （nullable/optional）
  final tsid = map['target_syndrome_id'];
  if (tsid != null) {
    if (tsid is String) {
      targetSyndromeId = tsid;
    } else {
      errors.add(
        TeacherValidationError(
          field: '$prefix.target_syndrome_id',
          message: '必须是字符串或 null',
        ),
      );
    }
  }

  // target_dimension （nullable/optional）
  final tdim = map['target_dimension'];
  if (tdim != null) {
    if (tdim is String) {
      if (_isValidDimension(tdim)) {
        targetDimension = tdim;
      } else {
        errors.add(
          TeacherValidationError(
            field: '$prefix.target_dimension',
            message: '非法 teacher 维度（实际: $tdim）',
          ),
        );
      }
    } else {
      errors.add(
        TeacherValidationError(
          field: '$prefix.target_dimension',
          message: '必须是字符串或 null',
        ),
      );
    }
  }

  // task_type
  final ttT = map['task_type'];
  if (ttT is String) {
    if (_isValidTaskType(ttT)) {
      taskType = ttT;
    } else {
      errors.add(
        TeacherValidationError(
          field: '$prefix.task_type',
          message: '必须是 rewrite | analyze | compare | generate（实际: $ttT）',
        ),
      );
    }
  } else {
    errors.add(
      TeacherValidationError(field: '$prefix.task_type', message: '必填字段'),
    );
  }

  // task_description
  final tdesc = map['task_description'];
  if (tdesc is String && tdesc.isNotEmpty) {
    taskDescription = tdesc;
  } else {
    errors.add(
      TeacherValidationError(
        field: '$prefix.task_description',
        message: '必须是非空字符串',
      ),
    );
  }

  // difficulty
  final diff = map['difficulty'];
  if (diff is String) {
    if (_isValidDifficulty(diff)) {
      difficulty = diff;
    } else {
      errors.add(
        TeacherValidationError(
          field: '$prefix.difficulty',
          message: '必须是 easy | medium | hard（实际: $diff）',
        ),
      );
    }
  } else {
    errors.add(
      TeacherValidationError(field: '$prefix.difficulty', message: '必填字段'),
    );
  }

  // evaluation_criteria
  final ec = map['evaluation_criteria'];
  if (ec is List) {
    final list = <String>[];
    bool ok = true;
    for (int i = 0; i < ec.length; i++) {
      final item = ec[i];
      if (item is String && item.isNotEmpty) {
        list.add(item);
      } else {
        errors.add(
          TeacherValidationError(
            field: '$prefix.evaluation_criteria[$i]',
            message: '必须是非空字符串',
          ),
        );
        ok = false;
      }
    }
    if (ok) evaluationCriteria = list;
  } else {
    errors.add(
      TeacherValidationError(
        field: '$prefix.evaluation_criteria',
        message: '必须是字符串数组',
      ),
    );
  }

  if (errors.isNotEmpty) return null;
  return TrainingTask(
    targetSyndromeId: targetSyndromeId,
    targetDimension: targetDimension,
    taskType: taskType!,
    taskDescription: taskDescription!,
    difficulty: difficulty!,
    evaluationCriteria: evaluationCriteria!,
  );
}

