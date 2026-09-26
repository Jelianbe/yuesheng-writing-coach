// ─────────────────────────────────────────────────────────────
// GrowthOverviewCard — 成长总览卡（品牌色卡）
// 真源：yuesheng-android/src/components/profile/GrowthOverviewCard.tsx
//
// 视觉（月色竹青）：竹青底圆角卡 + 月笙头像 + 三统计
// （累计创作/诊断次数/已解决问题）+ 详情链接
//
// 批次 51b：Flutter GrowthDetailPage 对齐 RN growth-detail.tsx 组件层落地。
// 数据源 GrowthOverview（growth_service.dart，批次 51a）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/shared_constants.dart';
import '../../config/app_palette.dart';

/// 成长总览卡
class GrowthOverviewCard extends StatelessWidget {
  final int totalWords;
  final int diagnosisCount;
  final int resolvedCount;

  /// 批次61：AI 介入次数（诊断+训练），依赖度信号
  final int aiInterventions;
  final VoidCallback? onViewDetail;

  const GrowthOverviewCard({
    super.key,
    required this.totalWords,
    required this.diagnosisCount,
    required this.resolvedCount,
    this.aiInterventions = 0,
    this.onViewDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.primary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileRow(context),
          const SizedBox(height: AppSpacing.lg),
          _buildStatsRow(context),
          if (onViewDetail != null) ..._buildDetailLink(context),
        ],
      ),
    );
  }

  /// Profile row：头像 + 姓名/状态
  Widget _buildProfileRow(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: context.palette.onPrimaryFaint,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '月',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.palette.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '月笙',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.palette.onPrimary,
              ),
            ),
            SizedBox(height: 2),
            Text(
              '写作提升中',
              style: TextStyle(
                fontSize: 12,
                color: context.palette.onPrimaryDim,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Stats row：累计创作 / 诊断次数 / AI 介入 / 已解决问题
  Widget _buildStatsRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _StatItem(
          value: formatWordCount(totalWords),
          label: '累计创作',
          valueColor: context.palette.onPrimary,
        ),
        _StatItem(
          value: '$diagnosisCount',
          label: '诊断次数',
          valueColor: context.palette.onPrimary,
        ),
        _StatItem(
          value: '$aiInterventions',
          label: 'AI 介入',
          valueColor: context.palette.onPrimary,
        ),
        _StatItem(
          value: '$resolvedCount',
          label: '已解决问题',
          valueColor: context.palette.l1,
        ),
      ],
    );
  }

  /// 详情入口：诊断历史 / 成长详情
  List<Widget> _buildDetailLink(BuildContext context) {
    return [
      const SizedBox(height: AppSpacing.md),
      Container(height: 1, color: context.palette.onPrimaryFaint),
      const SizedBox(height: AppSpacing.md),
      InkWell(
        onTap: onViewDetail,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '诊断历史 / 成长详情',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.palette.onPrimary,
                ),
              ),
            ),
            Text(
              '›',
              style: TextStyle(
                fontSize: 20,
                color: context.palette.onPrimaryDim,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;

  const _StatItem({
    required this.value,
    required this.label,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.palette.onPrimaryDim),
        ),
      ],
    );
  }
}
