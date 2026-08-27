// ─────────────────────────────────────────────────────────────
// mastery_evidence — 多证据掌握（FT-06，Evidence-Based Mastery）
//
// 依据：架构真源 FT-06 — 假掌握问题，学员写出一个好比喻就认为掌握了整体修辞能力。
//   借鉴：掌握信号多证据 + 复习/推进门控。
//   设计哲学第 3 条：掌握必须有证据，差距：缺多证据要求（解释+信心+近迁移）。
//
// 本模块为多证据基础设施，不修改现有 transitionTeachingState（向后兼容）。
// 未来在 consolidating → mastered 迁移中叠加本模块作为额外门控。
//
// 三维度：
//   1. 解释证据（Explanation）：学员能否解释为什么这样改
//   2. 信心证据（Confidence）：学员的自我评估信心水平
//   3. 近迁移证据（Near-Transfer）：学员能否在类似但不同的场景中应用
// ─────────────────────────────────────────────────────────────

/// 解释证据（学员能否解释为什么这样改）
class ExplanationEvidence {
  /// 学员给出的有效解释条目数
  final int validCount;

  /// 阈值：至少几条有效解释才算充分（默认 2）
  static const int kThreshold = 2;

  const ExplanationEvidence({required this.validCount});

  bool get isSufficient => validCount >= kThreshold;
}

/// 信心证据（学员的自我评估信心水平）
class ConfidenceEvidence {
  /// 信心评级（1-5 分，5 为最高）
  final int rating;

  /// 阈值：至少几分才算充分（默认 3）
  static const int kThreshold = 3;

  const ConfidenceEvidence({required this.rating});

  bool get isSufficient => rating >= kThreshold;
}

/// 近迁移证据（学员能否在类似但不同的场景中应用）
class NearTransferEvidence {
  /// 迁移场景数（不同场景的正确应用次数）
  final int scenarioCount;

  /// 阈值：至少几个不同场景才算充分（默认 1）
  static const int kThreshold = 1;

  const NearTransferEvidence({required this.scenarioCount});

  bool get isSufficient => scenarioCount >= kThreshold;
}

/// 多证据掌握入参
class MasteryEvidence {
  final ExplanationEvidence? explanation;
  final ConfidenceEvidence? confidence;
  final NearTransferEvidence? nearTransfer;

  const MasteryEvidence({
    this.explanation,
    this.confidence,
    this.nearTransfer,
  });
}

/// 多证据评估结果
class MasteryEvidenceVerdict {
  /// 是否通过多证据门控（三维度都充分）
  final bool passed;

  /// 缺失的维度名称列表（未通过时非空）
  final List<String> missingDimensions;

  const MasteryEvidenceVerdict({
    required this.passed,
    required this.missingDimensions,
  });
}

/// 评估多证据是否充分（纯函数，可单测）
///
/// 三维度都充分 → 通过
/// 任一维度缺失或不充分 → 不通过 + 标注缺失维度
///
/// 防御性处理：null 维度视为缺失（降级为不充分）
MasteryEvidenceVerdict evaluateMasteryEvidence(MasteryEvidence evidence) {
  final missing = <String>[];

  if (evidence.explanation == null || !evidence.explanation!.isSufficient) {
    missing.add('explanation');
  }
  if (evidence.confidence == null || !evidence.confidence!.isSufficient) {
    missing.add('confidence');
  }
  if (evidence.nearTransfer == null || !evidence.nearTransfer!.isSufficient) {
    missing.add('nearTransfer');
  }

  return MasteryEvidenceVerdict(
    passed: missing.isEmpty,
    missingDimensions: missing,
  );
}
