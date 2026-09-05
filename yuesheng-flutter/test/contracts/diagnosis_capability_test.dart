// ─────────────────────────────────────────────────────────────
// 契约测试 — 诊断能力
//
// 验证 DiagnosisCapability 接口可被现有实现 DiagnosisCapabilityImpl 满足
//（编译期 implements 断言 + 实例方法行为校验，天然规避同名方法自递归）。
//
// 这不是行为测试——行为由 test/services/diagnosis_*_test.dart 覆盖。
// 契约测试只验证「接口形状」稳定，为依赖倒置提供安全网。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/diagnosis_capability.dart';
import 'package:writingcoach/contracts/capability_registry.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';
import 'package:writingcoach/services/chat_training_parser.dart';
import 'package:writingcoach/types/teaching_types.dart';

import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
void main() {
  group('DiagnosisCapability 契约', () {
    test('接口在注册表中注册', () {
      expect(
        CapabilityContractRegistry.contractTypes,
        contains(DiagnosisCapability),
      );
    });

    test('DiagnosisCapabilityImpl 满足契约（编译期 implements 断言 + 行为）', () {
      final impl = DiagnosisCapabilityImpl();
      expect(impl, isA<DiagnosisCapability>());

      // parseDiagnosis：经契约实例方法消费，委托到顶层函数，不自递归
      final parsed = impl.parseDiagnosis('无诊断块的普通文本');
      expect(parsed, isA<ParseResult>());
      expect(parsed.displayContent, '无诊断块的普通文本');
      expect(parsed.diagnosis, isNull);

      // validateDiagnosisOutput：空 JSON → 不通过，但返回结构化结果
      final validated = impl.validateDiagnosisOutput('文本', {});
      expect(validated, isA<FullValidationResult>());
      expect(validated.passed, isFalse);

      // parseTrainingResult：委托到顶层函数，不自递归
      final trained = impl.parseTrainingResult('你的练习已达标');
      expect(trained, isA<TrainingResult?>());
      expect(trained, TrainingResult.passed);
    });

    test('顶层纯函数行为（向后兼容）', () {
      final parsed = parseDiagnosis('无诊断块的普通文本');
      expect(parsed, isA<ParseResult>());
      expect(parsed.diagnosis, isNull);

      final validated = validateDiagnosisOutput('文本', {});
      expect(validated, isA<FullValidationResult>());

      final trained = parseTrainingResult('你的练习已达标');
      expect(trained, TrainingResult.passed);
    });
  });
}
