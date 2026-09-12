// ─────────────────────────────────────────────────────────────
// growth_detail_syndrome_groups — 成长详情页症候分布分组渲染
//
// 从 growth_content.dart（原 part）真分解而来（R-019：原 part 伪拆分根除）。
//   - GrowthSyndromeGroupList 按教学状态分组渲染症候列表（批次 48）
//   - GrowthSyndromeCard      单条症候卡（症候名 + 严重度 + 教学状态徽章）
//
// 无状态纯渲染，数据经构造注入（[state] / [profile]）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../providers/growth_providers.dart';
import '../types/teaching_types.dart';
import 'growth_detail_widgets.dart';
import 'teaching_state_badge.dart';

/// 按教学状态分组渲染症候列表（批次 48，对齐 RN syndromeGroups 顺序：
/// in_progress → identified → consolidating → mastered）
class GrowthSyndromeGroupList extends StatelessWidget {
  final GrowthState state;
  final StudentProfile? profile;

  const GrowthSyndromeGroupList({
    super.key,
    required this.state,
    required this.profile,
  });

  /// 分组顺序（RN StudentProfilePanel.tsx renderSyndromeGroup 调用顺序）
  static const List<TeachingState> _order = [
    TeachingState.inProgress,
    TeachingState.identified,
    TeachingState.consolidating,
    TeachingState.mastered,
  ];

  /// 分组标题
  static const Map<TeachingState, String> _titles = {
    TeachingState.inProgress: '练习中',
    TeachingState.identified: '待诊断',
    TeachingState.consolidating: '巩固中',
    TeachingState.mastered: '已掌握',
  };

  /// 症候 → 教学状态（画像聚合；无画像记录时归入 identified，
  /// 对齐 RN byState ?? identified 兜底）
  TeachingState _stateOf(ActiveProblemView p) {
    final agg = profile?.syndromeProfile[p.syndromeId];
    return agg?.teachingState ?? TeachingState.identified;
  }

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (final ts in _order) {
      final items = state.activeProblems
          .where((p) => _stateOf(p) == ts)
          .toList();
      if (items.isEmpty) continue;
      widgets.add(_buildGroupTitle(_titles[ts]!));
      for (final problem in items) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: GrowthSyndromeCard(problem: problem, profile: profile),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildGroupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        top: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

/// 单条症候卡（症候名 + 严重度文本 + 教学状态徽章 + 严重度 chip）
class GrowthSyndromeCard extends StatelessWidget {
  final ActiveProblemView problem;
  final StudentProfile? profile;

  const GrowthSyndromeCard({
    super.key,
    required this.problem,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final agg = profile?.syndromeProfile[problem.syndromeId];
    return GrowthInfoCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    problem.syndromeName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '严重度 ${problem.severity}',
                    style: AppTextStyles.noteCaption,
                  ),
                ],
              ),
            ),
            // 教学状态徽章（画像聚合：profile.syndromeProfile[症候ID]）
            if (agg != null)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: TeachingStateBadge(
                  state: agg.teachingState,
                  size: TeachingStateBadgeSize.sm,
                  showLabel: true,
                ),
              ),
            SeverityChip(severity: problem.severity),
          ],
        ),
      ),
    );
  }
}
