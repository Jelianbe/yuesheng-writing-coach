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
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('validateSyndromeMutexWarnings（4.1 O6）', () {
    test('互斥对同时命中 → 返回对应 warning', () {
      final warnings = validateSyndromeMutexWarnings(['P006', 'P021']);
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('P006'));
      expect(warnings.first, contains('P021'));
    });

    test('三对互斥规则均生效（P015/P012、P009/P018）', () {
      expect(validateSyndromeMutexWarnings(['P015', 'P012']), hasLength(1));
      expect(validateSyndromeMutexWarnings(['P009', 'P018']), hasLength(1));
    });

    test('非互斥组合 → 无 warning', () {
      expect(validateSyndromeMutexWarnings(['P006', 'P003']), isEmpty);
      expect(validateSyndromeMutexWarnings(['P006']), isEmpty);
    });

    test('互斥对仅一侧命中 → 无 warning', () {
      expect(validateSyndromeMutexWarnings(['P021', 'P004']), isEmpty);
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
      expect(result.fixes.any((f) => f.type == 'V-02'), isFalse);
    });

    group('validateNaturalLanguage V-01/V-03/V-04（R-019 批次二补判据边界）', () {
      test('#N1 V-03 编号泄漏 → 替换 + 记录 fix', () {
        final result = validateNaturalLanguage('这里有 P001 与 A001 编号');
        expect(result.cleaned.contains('P001'), isFalse);
        expect(result.cleaned, contains('【症候】'));
        expect(result.cleaned, contains('【动作】'));
        expect(result.fixes.any((f) => f.type == 'V-03'), isTrue);
      });

      test('#N2 V-04 sensei 档含糖水词 → 拦截（valid=false）', () {
        final result = validateNaturalLanguage(
          '你写得真棒',
          attitude: AttitudeLevel.sensei,
        );
        expect(
          result.fixes.any((f) => f.type == 'V-04' && f.original == '真棒'),
          isTrue,
        );
        expect(result.valid, isFalse); // V-04 是阻断型
      });

      test('#N3 V-04 非 sensei 档含糖水词 → 不拦', () {
        final result = validateNaturalLanguage('你写得真棒');
        expect(result.fixes.any((f) => f.type == 'V-04'), isFalse);
      });

      test('#N4 V-01 恰好 80 字符无引号段落 → 不触发（阈值边界）', () {
        final longPara = '甲' * 80;
        final result = validateNaturalLanguage(longPara);
        expect(result.fixes.any((f) => f.type == 'V-01'), isFalse);
      });

      test('#N5 V-01 81 字符无引号段落 → 触发', () {
        final longPara = '甲' * 81;
        final result = validateNaturalLanguage(longPara);
        expect(result.fixes.any((f) => f.type == 'V-01'), isTrue);
      });
    });
  });
}
