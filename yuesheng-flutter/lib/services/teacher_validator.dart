// ─────────────────────────────────────────────────────────────
// Teacher Validator
// 复刻 yuesheng-android/src/services/teacher-validator.ts
//
// Schema 校验 + 业务一致性（decision↔task、判决词、症候ID泄漏）。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/config/shared_constants.dart';

// ─── 常量 ──────────────────────────────────────────────────────

const List<String> kTeachingDecisions = [
  'encourage',
  'guide',
  'train',
  'defer',
];
const List<String> kTaskTypes = ['rewrite', 'analyze', 'compare', 'generate'];
const List<String> kDifficultyLevels = ['easy', 'medium', 'hard'];

// 复用 editor 的 9 个维度
const List<String> kTeacherDimensions = [
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

bool _isValidDecision(String s) => kTeachingDecisions.contains(s);
bool _isValidTaskType(String s) => kTaskTypes.contains(s);
bool _isValidDifficulty(String s) => kDifficultyLevels.contains(s);
bool _isValidDimension(String s) => kTeacherDimensions.contains(s);

// 症候 ID 泄漏检测（P0 + 2位数字，与 RN SYNDROME_ID_PATTERN 一致）
final RegExp _syndromeIdPattern = RegExp(r'P0\d{2}');

// ─── 类型 ──────────────────────────────────────────────────────

class TrainingTask {
  final String? targetSyndromeId;
  final String? targetDimension;
  final String taskType;
  final String taskDescription;
  final String difficulty;
  final List<String> evaluationCriteria;

  const TrainingTask({
    this.targetSyndromeId,
    this.targetDimension,
    required this.taskType,
    required this.taskDescription,
    required this.difficulty,
    required this.evaluationCriteria,
  });
}

class TeacherResult {
  final String teachingDecision;
  final String teachingReason;
  final String naturalLanguage;
  final TrainingTask? trainingTask;

  /// 批次63（B62d）：位置清单——「标注位置自查」A 选项的数据源。
  /// 每项 = 段落位置 + 原文摘录（<=30字），供学员定位自查，AI 不改写正文。
  final List<String> locationMarks;

  const TeacherResult({
    required this.teachingDecision,
    required this.teachingReason,
    required this.naturalLanguage,
    this.trainingTask,
    this.locationMarks = const [],
  });
}

class TeacherValidationError {
  final String field;
  final String message;
  const TeacherValidationError({required this.field, required this.message});
}

class TeacherValidationResult {
  final bool valid;
  final List<TeacherValidationError> errors;
  final TeacherResult? data;
  const TeacherValidationResult({
    required this.valid,
    required this.errors,
    this.data,
  });
}

class TeacherConsistencyViolation {
  final String rule;
  final String severity;
  final String message;
  const TeacherConsistencyViolation({
    required this.rule,
    required this.severity,
    required this.message,
  });
}

class TeacherConsistencyResult {
  final bool passed;
  final List<TeacherConsistencyViolation> violations;
  const TeacherConsistencyResult({
    required this.passed,
    required this.violations,
  });
}

class FullTeacherValidationResult {
  final bool passed;
  final TeacherValidationResult schemaValidation;
  final TeacherConsistencyResult consistency;
  final TeacherResult? data;
  const FullTeacherValidationResult({
    required this.passed,
    required this.schemaValidation,
    required this.consistency,
    this.data,
  });
}

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

  final decisions = _validateDecisionFields(raw, errors);
  final trainingTask = _parseOptionalTrainingTask(raw, errors);
  final locationMarks = _parseLocationMarks(raw);

  if (errors.isNotEmpty) {
    return TeacherValidationResult(valid: false, errors: errors);
  }

  return TeacherValidationResult(
    valid: true,
    errors: const [],
    data: TeacherResult(
      teachingDecision: decisions.teachingDecision!,
      teachingReason: decisions.teachingReason!,
      naturalLanguage: decisions.naturalLanguage!,
      trainingTask: trainingTask,
      locationMarks: locationMarks,
    ),
  );
}

/// teaching_decision / teaching_reason / natural_language 校验（R-019 拆出）。
typedef _TeacherDecisionFields = ({
  String? teachingDecision,
  String? teachingReason,
  String? naturalLanguage,
});

_TeacherDecisionFields _validateDecisionFields(
  Map<String, dynamic> raw,
  List<TeacherValidationError> errors,
) {
  final teachingDecision = _parseDecisionValue(raw, errors);
  String? teachingReason;
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

  String? naturalLanguage;
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
  return (
    teachingDecision: teachingDecision,
    teachingReason: teachingReason,
    naturalLanguage: naturalLanguage,
  );
}

/// training_task 可选子块解析（R-019 拆出）。
TrainingTask? _parseOptionalTrainingTask(
  Map<String, dynamic> raw,
  List<TeacherValidationError> errors,
) {
  final tt = raw['training_task'];
  if (tt == null) return null;
  if (tt is! Map) {
    errors.add(
      const TeacherValidationError(field: 'training_task', message: '必须是对象或省略'),
    );
    return null;
  }
  final map = Map<String, dynamic>.from(tt);
  return _parseTrainingTask(map, 'training_task', errors);
}

/// location_marks 宽松解析（可选字段不阻断，R-019 拆出）。
List<String> _parseLocationMarks(Map<String, dynamic> raw) {
  final lm = raw['location_marks'];
  if (lm is! List) return const [];
  final list = <String>[];
  for (final item in lm) {
    if (item is String && item.isNotEmpty) {
      list.add(item);
    } else {
      return const [];
    }
  }
  return list;
}

TrainingTask? _parseTrainingTask(
  Map<String, dynamic> map,
  String prefix,
  List<TeacherValidationError> errors,
) {
  final ids = _parseOptionalIds(map, prefix, errors);
  final core = _parseTaskCoreFields(map, prefix, errors);
  final evaluationCriteria = _parseEvaluationCriteria(map, prefix, errors);

  if (errors.isNotEmpty) return null;
  return TrainingTask(
    targetSyndromeId: ids.targetSyndromeId,
    targetDimension: ids.targetDimension,
    taskType: core.taskType!,
    taskDescription: core.taskDescription!,
    difficulty: core.difficulty!,
    evaluationCriteria: evaluationCriteria!,
  );
}

/// target_syndrome_id / target_dimension（可选字段，R-019 拆出）。
typedef _TrainingOptionalIds = ({
  String? targetSyndromeId,
  String? targetDimension,
});

_TrainingOptionalIds _parseOptionalIds(
  Map<String, dynamic> map,
  String prefix,
  List<TeacherValidationError> errors,
) {
  String? targetSyndromeId;
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

  String? targetDimension;
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
  return (targetSyndromeId: targetSyndromeId, targetDimension: targetDimension);
}

/// task_type / task_description / difficulty 校验（R-019 拆出）。
typedef _TrainingTaskCore = ({
  String? taskType,
  String? taskDescription,
  String? difficulty,
});

_TrainingTaskCore _parseTaskCoreFields(
  Map<String, dynamic> map,
  String prefix,
  List<TeacherValidationError> errors,
) {
  String? taskType;
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

  String? taskDescription;
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

  final difficulty = _parseDifficultyValue(map, prefix, errors);
  return (
    taskType: taskType,
    taskDescription: taskDescription,
    difficulty: difficulty,
  );
}

/// teaching_decision 白名单校验（R-019 拆出）。
String? _parseDecisionValue(
  Map<String, dynamic> raw,
  List<TeacherValidationError> errors,
) {
  final td = raw['teaching_decision'];
  if (td is String) {
    if (_isValidDecision(td)) {
      return td;
    }
    errors.add(
      TeacherValidationError(
        field: 'teaching_decision',
        message: '必须是 encourage | guide | train | defer（实际: $td）',
      ),
    );
  } else {
    errors.add(
      const TeacherValidationError(field: 'teaching_decision', message: '必填字段'),
    );
  }
  return null;
}

/// difficulty 白名单校验（R-019 拆出）。
String? _parseDifficultyValue(
  Map<String, dynamic> map,
  String prefix,
  List<TeacherValidationError> errors,
) {
  final diff = map['difficulty'];
  if (diff is String) {
    if (_isValidDifficulty(diff)) {
      return diff;
    }
    errors.add(
      TeacherValidationError(
        field: '$prefix.difficulty',
        message: '必须是 easy | medium | hard（实际: $diff）',
      ),
    );
  } else {
    errors.add(
      TeacherValidationError(field: '$prefix.difficulty', message: '必填字段'),
    );
  }
  return null;
}

/// evaluation_criteria 校验（≥1 条 + 逐项，R-019 拆出）。
List<String>? _parseEvaluationCriteria(
  Map<String, dynamic> map,
  String prefix,
  List<TeacherValidationError> errors,
) {
  final ec = map['evaluation_criteria'];
  if (ec is! List) {
    errors.add(
      TeacherValidationError(
        field: '$prefix.evaluation_criteria',
        message: '必须是字符串数组',
      ),
    );
    return null;
  }
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
  return ok ? list : null;
}

// ─── 一致性检查 ────────────────────────────────────────────────

/// 教学输出一致性检查主入口：决策↔任务一致性 + 语言洁净度（判决词/症候 ID）。
TeacherConsistencyResult checkTeacherConsistency(TeacherResult result) {
  final violations = <TeacherConsistencyViolation>[];
  _checkDecisionTaskConsistency(result, violations);
  _checkLanguageHygiene(result, violations);
  final hasError = violations.any((v) => v.severity == 'error');
  return TeacherConsistencyResult(passed: !hasError, violations: violations);
}

/// decision ↔ training_task 一致性（encourage/defer 不带 task；guide/train 必须带）。
void _checkDecisionTaskConsistency(
  TeacherResult result,
  List<TeacherConsistencyViolation> violations,
) {
  if (result.teachingDecision == 'encourage' ||
      result.teachingDecision == 'defer') {
    if (result.trainingTask != null) {
      violations.add(
        TeacherConsistencyViolation(
          rule: 'NO_TASK_FOR_ENCOURAGE_DEFER',
          severity: 'warning',
          message: '${result.teachingDecision} 时不应有 training_task，但字段存在',
        ),
      );
    }
  }
  if (result.teachingDecision == 'guide' ||
      result.teachingDecision == 'train') {
    if (result.trainingTask == null) {
      violations.add(
        TeacherConsistencyViolation(
          rule: 'TASK_REQUIRED_FOR_GUIDE_TRAIN',
          severity: 'error',
          message: '${result.teachingDecision} 时 training_task 必填，但字段缺失',
        ),
      );
    }
  }
}

/// natural_language 洁净度（判决词 + 症候 ID 泄漏检查）。
void _checkLanguageHygiene(
  TeacherResult result,
  List<TeacherConsistencyViolation> violations,
) {
  final verdictHits = detectTeacherVerdictWords(result.naturalLanguage);
  if (verdictHits.isNotEmpty) {
    violations.add(
      TeacherConsistencyViolation(
        rule: 'NO_VERDICT_WORDS',
        severity: 'error',
        message: 'natural_language 含判决词: [${verdictHits.join(', ')}]',
      ),
    );
  }
  final syndromeHits = detectSyndromeIdLeak(result.naturalLanguage);
  if (syndromeHits.isNotEmpty) {
    violations.add(
      TeacherConsistencyViolation(
        rule: 'NO_SYNDROME_ID_LEAK',
        severity: 'error',
        message: 'natural_language 泄漏症候 ID: [${syndromeHits.join(', ')}]',
      ),
    );
  }
}

// ─── 完整校验入口 ──────────────────────────────────────────────

FullTeacherValidationResult validateTeacherOutput(Object? raw) {
  final schemaValidation = validateTeacherSchema(raw);
  if (!schemaValidation.valid || schemaValidation.data == null) {
    return FullTeacherValidationResult(
      passed: false,
      schemaValidation: schemaValidation,
      consistency: const TeacherConsistencyResult(passed: true, violations: []),
    );
  }
  final consistency = checkTeacherConsistency(schemaValidation.data!);
  return FullTeacherValidationResult(
    passed: consistency.passed,
    schemaValidation: schemaValidation,
    consistency: consistency,
    data: consistency.passed ? schemaValidation.data : null,
  );
}

// ─── 格式化 ────────────────────────────────────────────────────

String formatTeacherErrors(FullTeacherValidationResult result) {
  final parts = <String>[];
  if (!result.schemaValidation.valid) {
    parts.add('[Schema 校验] ${result.schemaValidation.errors.length} 个错误:');
    for (final e in result.schemaValidation.errors) {
      parts.add('  - ${e.field}: ${e.message}');
    }
  }
  if (!result.consistency.passed || result.consistency.violations.isNotEmpty) {
    final ec = result.consistency.violations
        .where((v) => v.severity == 'error')
        .length;
    final wc = result.consistency.violations
        .where((v) => v.severity == 'warning')
        .length;
    parts.add('[一致性] $ec 个 error, $wc 个 warning:');
    for (final v in result.consistency.violations) {
      parts.add('  - [${v.severity}] ${v.rule}: ${v.message}');
    }
  }
  return parts.join('\n');
}
