// ─────────────────────────────────────────────────────────────
// 契约测试 — 诊断能力
//
// 验证 DiagnosisCapability 接口可被现有实现满足，
// 且方法签名（返回类型/参数类型）与实际调用一致。
//
// 这不是行为测试——行为由 test/services/diagnosis_*_test.dart 覆盖。
// 契约测试只验证「接口形状」稳定，为后续依赖倒置提供安全网。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/diagnosis_capability.dart';
import 'package:writingcoach/contracts/capability_registry.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/diagnosis_validator.dart';
import 'package:writingcoach/services/chat_training_parser.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('DiagnosisCapability 契约', () {
    test('接口在注册表中注册', () {
      expect(
        CapabilityContractRegistry.contractTypes,
        contains(DiagnosisCapability),
      );
    });

    test('parseDiagnosis 返回 ParseResult', () {
      final result = parseDiagnosis('无诊断块的普通文本');
      expect(result, isA<ParseResult>());
      expect(result.displayContent, '无诊断块的普通文本');
      expect(result.diagnosis, isNull);
    });

    test('validateDiagnosisOutput 返回 FullValidationResult', () {
      final result = validateDiagnosisOutput('文本', {});
      expect(result, isA<FullValidationResult>());
    });

    test('parseTrainingResult 返回 TrainingResult?', () {
      final result = parseTrainingResult('你的练习已达标');
      expect(result, isA<TrainingResult?>());
      expect(result, TrainingResult.passed);
    });

    test('接口可被实现（implements 编译验证）', () {
      final impl = _DiagnosisContractAdapter();
      expect(impl, isA<DiagnosisCapability>());
    });
  });
}

/// 最小适配器：将现有函数包装为 DiagnosisCapability 实现。
///
/// 此类的存在即证明接口可被满足——如果接口签名与现有实现冲突，
/// 编译期就会报错，无需运行时发现。
class _DiagnosisContractAdapter implements DiagnosisCapability {
  @override
  ParseResult parseDiagnosis(String rawText) => parseDiagnosisRaw(rawText);

  @override
  FullValidationResult validateDiagnosisOutput(
    String displayContent,
    Map<String, dynamic> rawJson,
  ) =>
      validateDiagnosisOutputRaw(displayContent, rawJson);

  @override
  TrainingResult? parseTrainingResult(String content) =>
      parseTrainingResultRaw(content);
}

// 顶层函数别名，避免与接口方法名冲突
ParseResult parseDiagnosisRaw(String rawText) => parseDiagnosis(rawText);

FullValidationResult validateDiagnosisOutputRaw(
  String displayContent,
  Map<String, dynamic> rawJson,
) =>
    validateDiagnosisOutput(displayContent, rawJson);

TrainingResult? parseTrainingResultRaw(String content) =>
    parseTrainingResult(content);
