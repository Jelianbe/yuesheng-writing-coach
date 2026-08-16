// ─────────────────────────────────────────────────────────────
// 学员画像 — 文本格式化
// 复刻 yuesheng-android/src/services/student-profile-format.ts
//
// 将结构化 profile 格式化为三步推理文本，注入 system message。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/services/student_profile_compute.dart';

String _severityLabel(Severity s) {
  switch (s) {
    case Severity.l1:
      return '轻微';
    case Severity.l2:
      return '中等';
    case Severity.l3:
      return '严重';
  }
}

String _proficiencyLabel(ProficiencyLevel p) {
  switch (p) {
    case ProficiencyLevel.beginner:
      return '初级写手';
    case ProficiencyLevel.elementary:
      return '入门写手';
    case ProficiencyLevel.intermediate:
      return '中级写手';
    case ProficiencyLevel.advanced:
      return '高级写手';
  }
}

String _teachingStateLabel(TeachingState s) {
  switch (s) {
    case TeachingState.identified:
      return '刚识别';
    case TeachingState.inProgress:
      return '训练中';
    case TeachingState.consolidating:
      return '趋稳中';
    case TeachingState.mastered:
      return '已掌握';
  }
}

String _cognitiveStyleLabel(CognitiveStyle s) {
  switch (s) {
    case CognitiveStyle.analytical:
      return '分析型思维';
    case CognitiveStyle.intuitive:
      return '直觉型思维';
    case CognitiveStyle.mixed:
      return '混合型思维';
  }
}

String _cognitiveStyleDesc(CognitiveStyle s) {
  switch (s) {
    case CognitiveStyle.analytical:
      return '偏好深度讲解';
    case CognitiveStyle.intuitive:
      return '偏好快速迭代';
    case CognitiveStyle.mixed:
      return '边练边讲';
  }
}

/// 格式化画像文本
///
/// 真源：student-profile-format.ts formatProfileText
String formatProfileText(
  StudentProfile profile,
  StagnationResult? stagnation,
  String? effectivenessText,
  OnboardingData? onboarding,
) {
  final sections = <String>[];
  sections.add('# 学员画像（三步推理，内部使用，不可对用户暴露编号）');
  sections.add('');

  // ── 学员初始画像 ──
  if (onboarding != null) {
    sections.add('【学员初始画像】');
    sections.add('- 写作经验：${_proficiencyLabel(onboarding.proficiency)}');
    if (onboarding.focusAreas.isNotEmpty) {
      sections.add('- 关注领域：${onboarding.focusAreas.join('、')}');
    }
    sections.add(
      '- 学习偏好：${_cognitiveStyleLabel(onboarding.cognitiveStyle)}（${_cognitiveStyleDesc(onboarding.cognitiveStyle)}）',
    );
    sections.add('- 写作目标：${onboarding.writingGoal}');
    sections.add('');
  }

  // ── 第一步：症候演化分析 ──
  sections.add('## 第一步：症候演化分析');
  sections.add('');
  final totalSyndromes = profile.syndromeProfile.length;
  final totalDiagnoses = profile.syndromeProfile.values.fold<int>(
    0,
    (sum, agg) => sum + agg.occurrenceCount,
  );
  sections.add(
    '从诊断历史来看，共识别 $totalSyndromes 个症候问题（累计 $totalDiagnoses 次诊断，跨 ${profile.totalSessions} 次对话）。',
  );
  sections.add('');

  // 按教学状态分组
  final byState = <TeachingState, List<SyndromeAggregation>>{
    TeachingState.inProgress: [],
    TeachingState.consolidating: [],
    TeachingState.mastered: [],
    TeachingState.identified: [],
  };
  for (final agg in profile.syndromeProfile.values) {
    byState[agg.teachingState] ??= <SyndromeAggregation>[];
    byState[agg.teachingState]!.add(agg);
  }

  // 按固定顺序输出
  for (final state in [
    TeachingState.inProgress,
    TeachingState.consolidating,
    TeachingState.mastered,
    TeachingState.identified,
  ]) {
    final items = byState[state];
    if (items == null || items.isEmpty) continue;
    sections.add('${_teachingStateLabel(state)}的症候：');
    for (final agg in items) {
      final trail = agg.severityHistory.length >= 2
          ? '，严重度轨迹 ${agg.severityHistory.map(_severityLabel).join('→')}'
          : '，当前 ${_severityLabel(agg.latestSeverity)}';
      String trendDesc;
      if (agg.trend == Trend.improving) {
        trendDesc = '（改善趋势）';
      } else if (agg.trend == Trend.worsening) {
        trendDesc = '（恶化趋势，需关注）';
      } else if (agg.trend == Trend.stable) {
        trendDesc = '（稳定）';
      } else {
        trendDesc = '（初现）';
      }
      sections.add('  - ${agg.syndromeName}：$trail$trendDesc');
    }
    sections.add('');
  }

  // ── 第二步：能力等级评估 ──
  sections.add('## 第二步：能力等级评估');
  sections.add('');

  final profLabel = _proficiencyLabel(profile.proficiency);
  final profReason = _buildProficiencyReason(profile);
  sections.add(
    '综合判断：$profLabel（置信度 ${(profile.confidence * 100).toStringAsFixed(0)}%）',
  );
  sections.add('依据：$profReason');
  sections.add('');

  if (profile.cognitiveStyle != null) {
    final styleLabel = _cognitiveStyleLabel(profile.cognitiveStyle!.style);
    sections.add(
      '认知风格：$styleLabel（置信度 ${(profile.cognitiveStyle!.confidence * 100).toStringAsFixed(0)}%）',
    );
    final styleBasis =
        profile.cognitiveStyle!.style == CognitiveStyle.analytical
        ? '分析型'
        : profile.cognitiveStyle!.style == CognitiveStyle.intuitive
        ? '直觉型'
        : '混合型';
    sections.add('依据：基于用户历史 $styleBasis 关键词使用频率推断');
    sections.add('');
  }

  if (stagnation != null && stagnation.stagnated) {
    sections.add('状态评估：停滞预警');
    sections.add('依据：${stagnation.reason}');
  } else if (totalDiagnoses >= 3) {
    final improvingCount = profile.syndromeProfile.values
        .where((agg) => agg.trend == Trend.improving)
        .length;
    sections.add('状态评估：正常推进');
    sections.add(
      '依据：${improvingCount > 0 ? "$improvingCount 个症候有改善趋势" : "已有教学记录，尚未出现停滞信号"}',
    );
  } else {
    sections.add('状态评估：初始阶段，数据不足');
  }
  sections.add('');

  // ── 第三步：教学策略建议 ──
  sections.add('## 第三步：教学策略建议');
  sections.add('');

  final prioritized = prioritizeSyndromes(profile.syndromeProfile);
  if (prioritized.isNotEmpty) {
    sections.add('按优先级排序：');
    final top3 = prioritized.length > 3
        ? prioritized.sublist(0, 3)
        : prioritized;
    for (int i = 0; i < top3.length; i++) {
      final p = top3[i];
      final agg = profile.syndromeProfile[p.id]!;
      final reason = _buildPriorityReason(agg);
      sections.add(
        '  ${i + 1}. ${p.name}（得分 ${p.score.toStringAsFixed(1)}）— $reason',
      );
    }
    sections.add('');
  }

  if (effectivenessText != null && effectivenessText.isNotEmpty) {
    final effLines = effectivenessText
        .split('\n')
        .where((l) => !l.startsWith('#') && !l.startsWith('---'));
    if (effLines.isNotEmpty) {
      sections.add('历史策略效果参考（过去尝试的教学方式）：');
      for (final line in effLines) {
        if (line.trim().isNotEmpty) sections.add('  $line');
      }
      sections.add('');
    }
  }

  sections.add('注意：以上三步推理由系统自动生成，仅供参考。实际教学方式请结合学员本轮的具体反馈灵活选择。');

  return sections.join('\n');
}

String _buildProficiencyReason(StudentProfile profile) {
  final allSeverities = profile.syndromeProfile.values
      .expand((agg) => agg.severityHistory)
      .toList();
  final l3Count = allSeverities.where((s) => s == Severity.l3).length;
  final l2Count = allSeverities.where((s) => s == Severity.l2).length;
  final l1Count = allSeverities.where((s) => s == Severity.l1).length;
  final total = allSeverities.length;

  final parts = <String>[];
  if (total > 0) parts.add('共 $total 次诊断');
  if (l3Count > 0) parts.add('L3（严重）$l3Count 次');
  if (l2Count > 0) parts.add('L2（中等）$l2Count 次');
  if (l1Count > 0) parts.add('L1（轻微）$l1Count 次');

  if (profile.proficiency == ProficiencyLevel.beginner) {
    return '${parts.join('，')}。频繁出现 L2/L3 严重度，判定为初级写手';
  }
  if (profile.proficiency == ProficiencyLevel.elementary) {
    return '${parts.join('，')}。处于基础要素积累阶段，判定为入门写手';
  }
  if (profile.proficiency == ProficiencyLevel.advanced) {
    return '${parts.join('，')}。最近 3+ 次均为 L1 轻微，判定为高级写手';
  }
  return '${parts.join('，')}。处于过渡阶段，判定为中级写手';
}

String _buildPriorityReason(SyndromeAggregation agg) {
  final parts = <String>[];
  parts.add('当前 ${_severityLabel(agg.latestSeverity)}');
  if (agg.trend == Trend.worsening) {
    parts.add('恶化趋势');
  } else if (agg.trend == Trend.improving) {
    parts.add('改善趋势');
  } else if (agg.trend == Trend.stable) {
    parts.add('稳定');
  }
  if (agg.teachingState == TeachingState.inProgress) {
    parts.add('训练中');
  } else if (agg.teachingState == TeachingState.consolidating) {
    parts.add('趋稳中');
  }
  return parts.join('，');
}
