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

// ─── 一致性检查 ────────────────────────────────────────────────

TeacherConsistencyResult checkTeacherConsistency(TeacherResult result) {
  final violations = <TeacherConsistencyViolation>[];

  // decision ↔ task 一致性
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

  // natural_language 判决词
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

  // natural_language 症候 ID 泄漏
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

  final hasError = violations.any((v) => v.severity == 'error');
  return TeacherConsistencyResult(passed: !hasError, violations: violations);
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
