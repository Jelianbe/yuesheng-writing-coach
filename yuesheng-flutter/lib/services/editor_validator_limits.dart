// ─────────────────────────────────────────────────────────────
// editor_validator 拆分：editor_validator_limits.dart（R-019 ≤300 行）
// 硬限制+入口+格式化：checkHardLimits/validateEditorOutput/formatEditorErrors。迁移自 editor_validator.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'editor_validator.dart';
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
