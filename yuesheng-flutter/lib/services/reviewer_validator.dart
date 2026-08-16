// ─────────────────────────────────────────────────────────────
// Reviewer Validator
// 复刻 yuesheng-android/src/services/reviewer-validator.ts
//
// 手写 Dart 校验（无 zod）：schema 校验 + 业务一致性检查。
// ─────────────────────────────────────────────────────────────

enum ReviewVerdict {
  pass('PASS'),
  fail('FAIL');

  final String value;
  const ReviewVerdict(this.value);
  static ReviewVerdict? fromString(String? s) {
    for (final v in ReviewVerdict.values) {
      if (v.value == s) return v;
    }
    return null;
  }
}

/// Reviewer 输出结果
/// 真源：reviewer-validator.ts ReviewerResult
class ReviewerResult {
  final String genre;
  final ReviewVerdict verdict;
  final List<String> matchedSignals;
  final String reason;
  final bool needsEditor;

  const ReviewerResult({
    required this.genre,
    required this.verdict,
    required this.matchedSignals,
    required this.reason,
    required this.needsEditor,
  });
}

class ValidationError {
  final String field;
  final String message;
  const ValidationError({required this.field, required this.message});
}

class ReviewerValidationResult {
  final bool valid;
  final List<ValidationError> errors;
  final ReviewerResult? data;
  const ReviewerValidationResult({
    required this.valid,
    required this.errors,
    this.data,
  });
}

class ConsistencyViolation {
  final String rule;
  final String message;
  const ConsistencyViolation({required this.rule, required this.message});
}

class ConsistencyResult {
  final bool passed;
  final List<ConsistencyViolation> violations;
  const ConsistencyResult({required this.passed, required this.violations});
}

class FullReviewerValidationResult {
  final bool passed;
  final ReviewerValidationResult schemaValidation;
  final ConsistencyResult consistency;
  final ReviewerResult? data;
  const FullReviewerValidationResult({
    required this.passed,
    required this.schemaValidation,
    required this.consistency,
    this.data,
  });
}

/// Schema 级校验
///
/// 复刻 zod ReviewerSchema.safeParse
ReviewerValidationResult validateReviewerSchema(Object? raw) {
  final errors = <ValidationError>[];
  if (raw is! Map<String, dynamic>) {
    return ReviewerValidationResult(
      valid: false,
      errors: const [ValidationError(field: '<root>', message: '必须是 JSON 对象')],
    );
  }

  String? genre;
  ReviewVerdict? verdict;
  List<String>? matchedSignals;
  String? reason;
  bool? needsEditor;

  // genre
  final g = raw['genre'];
  if (g is String && g.isNotEmpty) {
    genre = g;
  } else {
    errors.add(const ValidationError(field: 'genre', message: '必须是非空字符串'));
  }

  // verdict
  final v = raw['verdict'];
  if (v is String) {
    verdict = ReviewVerdict.fromString(v);
    if (verdict == null) {
      errors.add(
        ValidationError(field: 'verdict', message: '必须是 PASS | FAIL（实际: $v）'),
      );
    }
  } else {
    errors.add(const ValidationError(field: 'verdict', message: '必填字段'));
  }

  // matched_signals
  final ms = raw['matched_signals'];
  if (ms is List) {
    bool ok = true;
    final list = <String>[];
    for (int i = 0; i < ms.length; i++) {
      final item = ms[i];
      if (item is String && item.isNotEmpty) {
        list.add(item);
      } else {
        errors.add(
          ValidationError(field: 'matched_signals[$i]', message: '必须是非空字符串'),
        );
        ok = false;
      }
    }
    if (ok) matchedSignals = list;
  } else {
    errors.add(
      const ValidationError(field: 'matched_signals', message: '必须是字符串数组'),
    );
  }

  // reason
  final r = raw['reason'];
  if (r is String && r.isNotEmpty) {
    reason = r;
  } else {
    errors.add(const ValidationError(field: 'reason', message: '必须是非空字符串'));
  }

  // needs_editor
  final ne = raw['needs_editor'];
  if (ne is bool) {
    needsEditor = ne;
  } else {
    errors.add(const ValidationError(field: 'needs_editor', message: '必须是布尔值'));
  }

  if (errors.isNotEmpty) {
    return ReviewerValidationResult(valid: false, errors: errors);
  }

  return ReviewerValidationResult(
    valid: true,
    errors: const [],
    data: ReviewerResult(
      genre: genre!,
      verdict: verdict!,
      matchedSignals: matchedSignals!,
      reason: reason!,
      needsEditor: needsEditor!,
    ),
  );
}

/// 业务一致性检查
///
/// 真源：reviewer-validator.ts checkConsistency
ConsistencyResult checkConsistency(ReviewerResult result) {
  final violations = <ConsistencyViolation>[];

  if (result.verdict == ReviewVerdict.pass &&
      result.matchedSignals.isNotEmpty) {
    violations.add(
      ConsistencyViolation(
        rule: 'PASS_NO_SIGNALS',
        message:
            'PASS 时不应命中信号，但 matched_signals 有 ${result.matchedSignals.length} 条',
      ),
    );
  }

  if (result.verdict == ReviewVerdict.fail && result.matchedSignals.isEmpty) {
    violations.add(
      const ConsistencyViolation(
        rule: 'FAIL_NEEDS_SIGNALS',
        message: 'FAIL 时应至少命中 1 个信号，但 matched_signals 为空',
      ),
    );
  }

  return ConsistencyResult(passed: violations.isEmpty, violations: violations);
}

/// 完整校验入口
FullReviewerValidationResult validateReviewerOutput(Object? raw) {
  final schemaValidation = validateReviewerSchema(raw);
  if (!schemaValidation.valid || schemaValidation.data == null) {
    return FullReviewerValidationResult(
      passed: false,
      schemaValidation: schemaValidation,
      consistency: const ConsistencyResult(passed: true, violations: []),
    );
  }
  final consistency = checkConsistency(schemaValidation.data!);
  return FullReviewerValidationResult(
    passed: consistency.passed,
    schemaValidation: schemaValidation,
    consistency: consistency,
    data: consistency.passed ? schemaValidation.data : null,
  );
}

/// 格式化错误信息
String formatReviewerErrors(FullReviewerValidationResult result) {
  final parts = <String>[];
  if (!result.schemaValidation.valid) {
    parts.add('[Schema 校验] ${result.schemaValidation.errors.length} 个错误:');
    for (final e in result.schemaValidation.errors) {
      parts.add('  - ${e.field}: ${e.message}');
    }
  }
  if (!result.consistency.passed) {
    parts.add('[一致性] ${result.consistency.violations.length} 个违规:');
    for (final v in result.consistency.violations) {
      parts.add('  - ${v.rule}: ${v.message}');
    }
  }
  return parts.join('\n');
}
