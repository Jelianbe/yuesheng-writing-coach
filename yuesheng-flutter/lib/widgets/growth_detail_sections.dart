// ─────────────────────────────────────────────────────────────
// growth_detail_sections — 成长详情页各内容区块组件
//
// 从 growth_detail_content.dart 真分解而来（R-019：文件 ≤300 行硬上限）。
// 收纳内容区内的独立展示区块，使 growth_detail_content.dart 只保留
// 装配职责：
//   - GrowthEmptyState        空状态视图
//   - GrowthSectionTitle      区块标题
//   - GrowthAbilityProfileCard 能力画像卡片
//   - GrowthStyleProfileCard   写作风格卡片（含纠正入口）
//   - GrowthRecurrenceCard     同类症候复发率卡片
//
// 无状态纯渲染，数据与回调动经构造注入。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/growth_service.dart';
import '../types/teaching_types.dart';
import 'growth_detail_labels.dart';
import 'growth_detail_widgets.dart';
import 'proficiency_ring.dart';

/// 空状态视图（无诊断数据）
class GrowthEmptyState extends StatelessWidget {
  const GrowthEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        GrowthInfoCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                const Icon(
                  Icons.insights_outlined,
                  size: 32,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(height: 8),
                const Text(
                  '暂无诊断数据',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 区块标题（症候分布 / 同类症候复发率 / 诊断历史）
class GrowthSectionTitle extends StatelessWidget {
  final String title;
  final bool top;

  const GrowthSectionTitle(this.title, {super.key, required this.top});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xs,
        top: top ? AppSpacing.xs : 0,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// 能力画像卡片（ProficiencyRing + 认知风格 + 总会话数）
class GrowthAbilityProfileCard extends StatelessWidget {
  final StudentProfile? profile;

  const GrowthAbilityProfileCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final cognitiveStyle = profile?.cognitiveStyle;
    return GrowthInfoCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '能力画像',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ProficiencyRing(
                level: profile?.proficiency ?? ProficiencyLevel.beginner,
                confidence: profile?.confidence ?? 0,
              ),
            ),
            const SizedBox(height: 16),
            if (cognitiveStyle != null) ...[
              GrowthInfoRow(
                label: '认知风格',
                value: growthCognitiveStyleLabel(cognitiveStyle.style),
              ),
              const SizedBox(height: 8),
            ],
            GrowthInfoRow(
              label: '总会话数',
              value: '${profile?.totalSessions ?? 0}',
            ),
          ],
        ),
      ),
    );
  }
}

/// 写作风格卡片（批次53c：五维 + 总结；批次57：纠正入口）
class GrowthStyleProfileCard extends StatelessWidget {
  final WritingStyleProfile profile;
  final VoidCallback onOpenStyleCorrection;

  const GrowthStyleProfileCard({
    super.key,
    required this.profile,
    required this.onOpenStyleCorrection,
  });

  @override
  Widget build(BuildContext context) {
    return GrowthInfoCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            Text(
              profile.summary,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ..._buildDimensionRows(),
          ],
        ),
      ),
    );
  }

  /// 标题行（「写作风格」 + 「纠正」按钮）
  Widget _buildHeader() {
    return Row(
      children: [
        const Text(
          '写作风格',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        // 批次57：风格纠正入口（纠错非重写）
        TextButton(
          onPressed: onOpenStyleCorrection,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            '纠正',
            style: TextStyle(fontSize: 13, color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  /// 五维坐标信息行
  List<Widget> _buildDimensionRows() {
    return [
      GrowthInfoRow(label: '感官偏好', value: styleSensoryLabel(profile.sensory)),
      const SizedBox(height: 8),
      GrowthInfoRow(label: '节奏偏好', value: styleRhythmLabel(profile.rhythm)),
      const SizedBox(height: 8),
      GrowthInfoRow(
        label: '叙事距离',
        value: styleNarrativeLabel(profile.narrativeDistance),
      ),
      const SizedBox(height: 8),
      GrowthInfoRow(label: '语气质地', value: styleToneLabel(profile.toneTexture)),
      const SizedBox(height: 8),
      GrowthInfoRow(
        label: '结构本能',
        value: styleStructureLabel(profile.structure),
      ),
    ];
  }
}

/// 同类症候复发率卡片（批次65 B62h）
class GrowthRecurrenceCard extends StatelessWidget {
  final List<SyndromeRecurrence> recurrences;

  const GrowthRecurrenceCard({super.key, required this.recurrences});

  @override
  Widget build(BuildContext context) {
    return GrowthInfoCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '同一种问题，好转后是否再次出现',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < recurrences.length; i++) ...[
              GrowthRecurrenceRow(recurrence: recurrences[i]),
              if (i < recurrences.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
