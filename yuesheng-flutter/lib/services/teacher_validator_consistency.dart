// ─────────────────────────────────────────────────────────────
// teacher_validator 主题分组拆分：teacher_validator_consistency.dart（R-019 ≤300 行）
// checkTeacherConsistency + validateTeacherOutput + formatTeacherErrors。逐字迁移自 teacher_validator.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'teacher_validator.dart';
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
