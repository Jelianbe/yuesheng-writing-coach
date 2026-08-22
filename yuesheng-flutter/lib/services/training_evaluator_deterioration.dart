// ─────────────────────────────────────────────────────────────
// training_evaluator 主题分组拆分：training_evaluator_deterioration.dart（R-019 ≤300 行）
// 恶化检测：detectDeterioration + DeteriorationCheckInput/DeteriorationResult。逐字迁移自 training_evaluator.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'training_evaluator.dart';

class DeteriorationCheckInput {
  final String syndromeId;
  final Severity currentSeverity;
  final Severity previousSeverity;
  final bool wasResolvedToL1;
  final int consecutiveFailures;
  final bool reboundPattern;
  final int gapDays;
  final int newConcurrentSyndromes;

  const DeteriorationCheckInput({
    required this.syndromeId,
    required this.currentSeverity,
    required this.previousSeverity,
    required this.wasResolvedToL1,
    required this.consecutiveFailures,
    required this.reboundPattern,
    required this.gapDays,
    required this.newConcurrentSyndromes,
  });
}

/// 恶化检测结果
class DeteriorationResult {
  final DeteriorationSignal? signal;
  final String intervention;

  const DeteriorationResult({this.signal, required this.intervention});
}

/// 教学状态迁移输入
// ─── 恶化检测 ────────────────────────────────────────────────

/// 检测恶化信号并返回干预建议。
DeteriorationResult detectDeterioration(DeteriorationCheckInput input) {
  final currentSeverity = input.currentSeverity;
  final previousSeverity = input.previousSeverity;
  final wasResolvedToL1 = input.wasResolvedToL1;
  final consecutiveFailures = input.consecutiveFailures;
  final reboundPattern = input.reboundPattern;
  final gapDays = input.gapDays;
  final newConcurrentSyndromes = input.newConcurrentSyndromes;

  // 复发：已降至 L1 后再次 L2/L3
  if (wasResolvedToL1 && _kSeverityOrder[currentSeverity]! >= 2) {
    return const DeteriorationResult(
      signal: DeteriorationSignal.relapse,
      intervention: '回到 Lv.1 训练，换一种教学方式',
    );
  }

  // 恶化：连续 2 次 severity 上升
  if (_kSeverityOrder[currentSeverity]! > _kSeverityOrder[previousSeverity]! &&
      consecutiveFailures >= 2) {
    return const DeteriorationResult(
      signal: DeteriorationSignal.worsening,
      intervention: '停止训练该症候。改为自然语言讨论，寻找根本原因',
    );
  }

  // 新并发：新出现 ≥3 个症候
  if (newConcurrentSyndromes >= 3) {
    return const DeteriorationResult(
      signal: DeteriorationSignal.newConcurrent,
      intervention: '回到诊断确认阶段，让学员挑一个最关心的先练',
    );
  }

  // 反弹：连续 3 次达标后突然连续 2 次未达标
  if (reboundPattern) {
    return const DeteriorationResult(
      signal: DeteriorationSignal.rebound,
      intervention: '检查是否跳过了难度。如果是→降回之前的难度。如果不是→检查学员状态',
    );
  }

  // 巩固失败：间隔 > 7 天后 L2+
  if (gapDays > 7 && _kSeverityOrder[currentSeverity]! >= 2) {
    return const DeteriorationResult(
      signal: DeteriorationSignal.consolidationFail,
      intervention: 'FSRS 稳定度不足。增加该症候的训练频率',
    );
  }

  return const DeteriorationResult(signal: null, intervention: '');
}
