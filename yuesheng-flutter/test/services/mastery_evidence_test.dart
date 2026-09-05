// ─────────────────────────────────────────────────────────────
// FT-06 多证据掌握：单元测试
//
// 覆盖路径：
//   evaluateMasteryEvidence:
//     #1 空证据（三维度全 null）→ 不通过 + 三维度全缺失
//     #2 部分证据（仅一维度充分）→ 不通过 + 标注缺失维度
//     #3 完整证据（三维度都充分）→ 通过
//     #4 解释证据边界（validCount=1 不足 / validCount=2 充分）
//     #5 信心证据边界（rating=2 不足 / rating=3 充分）
//     #6 近迁移证据边界（scenarioCount=0 不足 / scenarioCount=1 充分）
//     #7 各维度单独缺失的组合
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/mastery_evidence.dart';

void main() {
  group('FT-06 evaluateMasteryEvidence', () {
    test('#1 空证据（三维度全 null）→ 不通过 + 三维度全缺失', () {
      final verdict = evaluateMasteryEvidence(const MasteryEvidence());
      expect(verdict.passed, isFalse);
      expect(verdict.missingDimensions.length, 3);
      expect(
        verdict.missingDimensions,
        containsAll(['explanation', 'confidence', 'nearTransfer']),
      );
    });

    test('#2 部分证据（仅解释维度充分）→ 不通过 + 标注缺失维度', () {
      final evidence = MasteryEvidence(
        explanation: const ExplanationEvidence(validCount: 3),
      );
      final verdict = evaluateMasteryEvidence(evidence);
      expect(verdict.passed, isFalse);
      expect(verdict.missingDimensions.length, 2);
      expect(
        verdict.missingDimensions,
        containsAll(['confidence', 'nearTransfer']),
      );
      expect(verdict.missingDimensions, isNot(contains('explanation')));
    });

    test('#3 完整证据（三维度都充分）→ 通过', () {
      final evidence = MasteryEvidence(
        explanation: const ExplanationEvidence(validCount: 2),
        confidence: const ConfidenceEvidence(rating: 3),
        nearTransfer: const NearTransferEvidence(scenarioCount: 1),
      );
      final verdict = evaluateMasteryEvidence(evidence);
      expect(verdict.passed, isTrue);
      expect(verdict.missingDimensions, isEmpty);
    });

    test('#4 解释证据边界（validCount=1 不足 / validCount=2 充分）', () {
      // 不足
      final evidence1 = MasteryEvidence(
        explanation: const ExplanationEvidence(validCount: 1),
        confidence: const ConfidenceEvidence(rating: 5),
        nearTransfer: const NearTransferEvidence(scenarioCount: 2),
      );
      final verdict1 = evaluateMasteryEvidence(evidence1);
      expect(verdict1.passed, isFalse);
      expect(verdict1.missingDimensions, contains('explanation'));

      // 充分
      final evidence2 = MasteryEvidence(
        explanation: const ExplanationEvidence(validCount: 2),
        confidence: const ConfidenceEvidence(rating: 5),
        nearTransfer: const NearTransferEvidence(scenarioCount: 2),
      );
      final verdict2 = evaluateMasteryEvidence(evidence2);
      expect(verdict2.passed, isTrue);
    });

    test('#5 信心证据边界（rating=2 不足 / rating=3 充分）', () {
      // 不足
      final evidence1 = MasteryEvidence(
        explanation: const ExplanationEvidence(validCount: 3),
        confidence: const ConfidenceEvidence(rating: 2),
        nearTransfer: const NearTransferEvidence(scenarioCount: 2),
      );
      final verdict1 = evaluateMasteryEvidence(evidence1);
      expect(verdict1.passed, isFalse);
      expect(verdict1.missingDimensions, contains('confidence'));

      // 充分
      final evidence2 = MasteryEvidence(
        explanation: const ExplanationEvidence(validCount: 3),
        confidence: const ConfidenceEvidence(rating: 3),
        nearTransfer: const NearTransferEvidence(scenarioCount: 2),
      );
      final verdict2 = evaluateMasteryEvidence(evidence2);
      expect(verdict2.passed, isTrue);
    });

    test('#6 近迁移证据边界（scenarioCount=0 不足 / scenarioCount=1 充分）', () {
      // 不足
      final evidence1 = MasteryEvidence(
        explanation: const ExplanationEvidence(validCount: 3),
        confidence: const ConfidenceEvidence(rating: 5),
        nearTransfer: const NearTransferEvidence(scenarioCount: 0),
      );
      final verdict1 = evaluateMasteryEvidence(evidence1);
      expect(verdict1.passed, isFalse);
      expect(verdict1.missingDimensions, contains('nearTransfer'));

      // 充分
      final evidence2 = MasteryEvidence(
        explanation: const ExplanationEvidence(validCount: 3),
        confidence: const ConfidenceEvidence(rating: 5),
        nearTransfer: const NearTransferEvidence(scenarioCount: 1),
      );
      final verdict2 = evaluateMasteryEvidence(evidence2);
      expect(verdict2.passed, isTrue);
    });

    test('#7 各维度单独缺失的组合', () {
      // 仅解释缺失
      final v1 = evaluateMasteryEvidence(
        MasteryEvidence(
          explanation: const ExplanationEvidence(validCount: 0),
          confidence: const ConfidenceEvidence(rating: 4),
          nearTransfer: const NearTransferEvidence(scenarioCount: 1),
        ),
      );
      expect(v1.passed, isFalse);
      expect(v1.missingDimensions, equals(['explanation']));

      // 仅信心缺失
      final v2 = evaluateMasteryEvidence(
        MasteryEvidence(
          explanation: const ExplanationEvidence(validCount: 2),
          confidence: const ConfidenceEvidence(rating: 1),
          nearTransfer: const NearTransferEvidence(scenarioCount: 1),
        ),
      );
      expect(v2.passed, isFalse);
      expect(v2.missingDimensions, equals(['confidence']));

      // 仅近迁移缺失
      final v3 = evaluateMasteryEvidence(
        MasteryEvidence(
          explanation: const ExplanationEvidence(validCount: 2),
          confidence: const ConfidenceEvidence(rating: 3),
          nearTransfer: const NearTransferEvidence(scenarioCount: 0),
        ),
      );
      expect(v3.passed, isFalse);
      expect(v3.missingDimensions, equals(['nearTransfer']));
    });
  });
}
