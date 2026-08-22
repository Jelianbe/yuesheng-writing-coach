// ─────────────────────────────────────────────────────────────
// teacher_validator 主题分组拆分：teacher_validator_types.dart（R-019 ≤300 行）
// 常量（kTeachingDecisions/kTaskTypes/kDifficultyLevels/kTeacherDimensions）+ 私有辅助 + 6 个 DTO 类（TrainingTask/TeacherResult/TeacherValidation*/TeacherConsistency*/FullTeacherValidationResult）。逐字迁移自 teacher_validator.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'teacher_validator.dart';
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
