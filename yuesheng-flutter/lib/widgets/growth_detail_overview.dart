// ─────────────────────────────────────────────────────────────
// growth_detail_overview — 成长详情页写作总览组件
//
// 从 growth_detail_page.dart 真分解而来（R-019：原 part 伪拆分根除）。
//   - GrowthOverviewGrid 写作总览六格网格（批次 51c，对齐 RN overviewGrid）
//   - GrowthGridItem     网格单格（值 + 标签）
//   - GrowthProgressLink 查看学习进度详情入口（批次 51c，对齐 RN progressLink）
//
// 无状态纯渲染，仅经构造注入数据与回调。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/growth_service.dart';
import '../services/progress_service.dart';
import '../types/teaching_types.dart';
import 'growth_detail_widgets.dart';

/// 写作总览六格网格（批次 51c，对齐 RN growth-detail overviewGrid：
/// 写作天数 / 当前阶段 / 已解决 / 待改进 + 首次/最近写作整宽两格）
class GrowthOverviewGrid extends StatelessWidget {
  final GrowthOverview overview;

  const GrowthOverviewGrid({super.key, required this.overview});

  String _phaseLabel(TeachingPhase phase) {
    return progressPhaseLabels[phase] ?? phase.value;
  }

  String _formatDate(int? ts) {
    if (ts == null) return '暂无';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${d.month}月${d.day}日';
  }

  @override
  Widget build(BuildContext context) {
    return GrowthInfoCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '写作总览',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ..._buildGridRows(),
          ],
        ),
      ),
    );
  }

  /// 六格网格内容（两行双列 + 两个整宽）
  List<Widget> _buildGridRows() {
    return [
      Row(
        children: [
          Expanded(
            child: GrowthGridItem(
              value: '${overview.writingDays}',
              label: '写作天数',
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GrowthGridItem(
              value: _phaseLabel(overview.currentPhase),
              label: '当前阶段',
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: GrowthGridItem(
              value: '${overview.totalResolved}',
              label: '已解决',
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GrowthGridItem(
              value: '${overview.totalActive}',
              label: '待改进',
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      GrowthGridItem(
        value: _formatDate(overview.firstWritingAt),
        label: '首次写作',
      ),
      const SizedBox(height: 12),
      GrowthGridItem(value: _formatDate(overview.lastWritingAt), label: '最近写作'),
    ];
  }
}

/// 网格单格（大号值 + 小号标签）
class GrowthGridItem extends StatelessWidget {
  final String value;
  final String label;

  const GrowthGridItem({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.microCaption),
      ],
    );
  }
}

/// 查看学习进度详情链接（批次 51c，对齐 RN growth-detail progressLink）
class GrowthProgressLink extends StatelessWidget {
  final VoidCallback onTap;

  const GrowthProgressLink({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 14,
          ),
          child: const Row(
            children: [
              Expanded(
                child: Text(
                  '查看学习进度详情',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Text(
                '›',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
