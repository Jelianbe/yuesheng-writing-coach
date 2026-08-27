// ─────────────────────────────────────────────────────────────
// SyndromeHistoryList — 症候追踪历史（发现/解决事件时间线）
// 真源：yuesheng-android/src/components/profile/SyndromeHistoryList.tsx
//
// 视觉（月色竹青）：卡片 + 时间线（圆点 + 竖线 + 症候名 + 事件徽章
// + 严重度色字 + 时间）。resolved 圆点绿色、detected 圆点按严重度色
//
// 批次 51b：Flutter GrowthDetailPage 对齐 RN growth-detail.tsx 组件层落地。
// 数据源 SyndromeHistoryEvent（growth_service.dart，批次 51a）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/growth_service.dart';
import '../types/teaching_types.dart';

/// 症候追踪历史
class SyndromeHistoryList extends StatelessWidget {
  final List<SyndromeHistoryEvent> events;
  final int? limit;

  const SyndromeHistoryList({super.key, required this.events, this.limit});

  @override
  Widget build(BuildContext context) {
    final displayed = limit != null && events.length > limit!
        ? events.sublist(0, limit)
        : events;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: AppColors.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '症候追踪历史',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '问题发现与解决的时间线',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (displayed.isEmpty)
                        const _EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: '暂无症候记录',
                          description: '完成诊断后，这里会显示问题发现与解决的时间线',
                        )
                      else ...[
                        for (var i = 0; i < displayed.length; i++) ...[
                          _TimelineItem(
                            event: displayed[i],
                            isLast: i == displayed.length - 1,
                          ),
                        ],
                        if (limit != null && events.length > limit!)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: Center(
                              child: Text(
                                '共 ${events.length} 条记录',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final SyndromeHistoryEvent event;
  final bool isLast;

  const _TimelineItem({required this.event, required this.isLast});

  /// 严重度色（复刻 RN severityColor）
  static Color _severityColor(Severity severity) {
    switch (severity) {
      case Severity.l1:
        return AppColors.l1Text;
      case Severity.l2:
        return AppColors.l2Text;
      case Severity.l3:
        return AppColors.l3Text;
    }
  }

  static const Map<String, String> _severityLabels = {
    'L1': '轻微',
    'L2': '中等',
    'L3': '严重',
  };

  String _formatTime(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}月${dt.day}日 $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final isResolved = event.eventType == 'resolved';
    final accentColor = isResolved
        ? AppColors.success
        : _severityColor(event.severity);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间线左侧：圆点 + 竖线
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.only(top: AppSpacing.xxs),
                      color: AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 内容
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.syndromeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isResolved
                              ? AppColors.success
                              : AppColors.danger,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          isResolved ? '解决' : '发现',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        _severityLabels[event.severity.value] ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _severityColor(event.severity),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        _formatTime(event.timestamp),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
