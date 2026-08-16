// ─────────────────────────────────────────────────────────────
// diagnosis_validator_test — 诊断校验器测试（批次4 补充）
//
// 覆盖：
//   validateSyndromeMutexWarnings（4.1 O6）:
//     1. 互斥对同时命中 → 返回对应 warning
//     2. 非互斥组合 → 无 warning
//   validateDiagnosisSchema（4.1）:
//     3. 含互斥对 → valid=true + warnings 非空（warning 级不阻断）
//     4. 无互斥对 → valid=true + warnings 空
//   validateNaturalLanguage V-02（4.6）:
//     5. "你应该/你务必" 类判决句命中共享词表 → 产生 V-02 fix
//     6. 非判决句 → 无 V-02 fix
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/diagnosis_validator.dart';

void main() {
  group('validateSyndromeMutexWarnings（4.1 O6）', () {
    test('互斥对同时命中 → 返回对应 warning', () {
      final warnings = validateSyndromeMutexWarnings(['P006', 'P021']);
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('P006'));
      expect(warnings.first, contains('P021'));
    });

    test('三对互斥规则均生效（P015/P012、P009/P018）', () {
      expect(
        validateSyndromeMutexWarnings(['P015', 'P012']),
        hasLength(1),
      );
      expect(
        validateSyndromeMutexWarnings(['P009', 'P018']),
        hasLength(1),
      );
    });

    test('非互斥组合 → 无 warning', () {
      expect(
        validateSyndromeMutexWarnings(['P006', 'P003']),
        isEmpty,
      );
      expect(
        validateSyndromeMutexWarnings(['P006']),
        isEmpty,
      );
    });

    test('互斥对仅一侧命中 → 无 warning', () {
      expect(
        validateSyndromeMutexWarnings(['P021', 'P004']),
        isEmpty,
      );
    });
  });

  group('validateDiagnosisSchema（4.1 warning 不阻断）', () {
    Map<String, dynamic> validDiagnosis(List<String> syndromeIds) {
      return {
        'syndromes': [
          for (final id in syndromeIds)
            {
              'syndrome_id': id,
              'name': '症候$id',
              'severity': 'L2',
              'evidence': ['证据'],
              'explanation': '解释',
            },
        ],
        'suggested_actions': ['动作1'],
        'confidence': 0.8,
      };
    }

    test('含互斥对 → valid=true 且 warnings 非空（不阻断落库）', () {
      final result = validateDiagnosisSchema(
        validDiagnosis(['P006', 'P021', 'P003']),
      );
      expect(result.valid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('P006/P021'));
    });

    test('无互斥对 → valid=true 且 warnings 空', () {
      final result = validateDiagnosisSchema(
        validDiagnosis(['P006', 'P003', 'P004']),
      );
      expect(result.valid, isTrue);
      expect(result.warnings, isEmpty);
    });
  });

  group('validateNaturalLanguage V-02 判决词（4.6 共享常量）', () {
    test('"你应该" → 命中 V-02（仅记录不阻断）', () {
      final result = validateNaturalLanguage('你应该调整一下这段的结构');
      final v02 = result.fixes.where((f) => f.type == 'V-02');
      expect(v02, isNotEmpty);
      expect(v02.first.original, '你应该');
      expect(result.valid, isTrue); // V-02 非真拦截
    });

    test('"你务必" → 命中 V-02', () {
      final result = validateNaturalLanguage('你务必先写完这个情节');
      expect(
        result.fixes.any((f) => f.type == 'V-02' && f.original == '你务必'),
        isTrue,
      );
    });

    test('非判决句 → 无 V-02', () {
      final result = validateNaturalLanguage('这一段的人物动机可以再明确一点');
      expect(
        result.fixes.any((f) => f.type == 'V-02'),
        isFalse,
      );
    });
  });
}
